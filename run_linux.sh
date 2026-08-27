#!/usr/bin/env bash
# Install and launch the bot on a Linux server inside a detachable tmux session,
# supervised so it comes back on its own after a Telegram-triggered self-update
# or a crash.
#
# Deploy: drop this file into an empty folder and run it. On first run it
# installs curl + tmux (apt / dnf / yum / zypper / pacman / apk) and downloads
# the binary for this machine's architecture
# - a new server needs no manual setup. The encryption key is the bot's own
# business: it mints data/master.key on first boot. Drop a `.env` next to the
# binary only to pin a specific KG_MASTER_KEY (a migrated database, a key from a
# secret store) - the script sources it when present.
# Point BOT_DIR elsewhere to install into another folder:
#   BOT_DIR=/opt/knopka-groshu ./run_linux.sh
#
# Usage:
#   ./run_linux.sh    first run installs everything, starts the bot, attaches
#                     later runs just reattach - safe to re-run
#   Ctrl-b then d     detach, leaving the bot running
#   tmux attach -t knopka-groshu    reattach by hand
#
# Why the loop: after a self-update the bot swaps its own binary and exits 0,
# expecting a supervisor to bring it back (INVOCATION_ID below is what tells it
# one exists). Without the loop it prints "please rerun the binary" and stays
# down. Settings-change restarts do NOT go through here - those execvp in place,
# same PID, same pane, and the loop never notices.

set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SESSION=knopka-groshu
RELEASES_REPO=envoydev/knopka-groshu-trading-bot
BOT_DIR="${BOT_DIR:-$(dirname "$SELF")}"

mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# Outside tmux: install deps, fetch the binary, seed the master key, hand off
# into the session, attach. The handoff re-runs this same file inside the pane,
# which is why the tmux install can never end up executing from within tmux.
if [ -z "${TMUX:-}" ]; then
    # Root already has privileges, and minimal server images often ship without
    # sudo at all - calling it unconditionally would fail for no reason.
    sudo_cmd=""
    if [ "$(id -u)" -ne 0 ]; then
        sudo_cmd=sudo
    fi

    missing=""
    command -v curl >/dev/null || missing="$missing curl"
    command -v tmux >/dev/null || missing="$missing tmux"

    if [ -n "$missing" ]; then
        echo "  ↓ Installing:$missing"
        # shellcheck disable=SC2086  # $missing is a deliberate word-split package list
        if   command -v apt-get >/dev/null; then $sudo_cmd apt-get update && $sudo_cmd apt-get install -y $missing
        elif command -v dnf     >/dev/null; then $sudo_cmd dnf install -y $missing
        elif command -v yum     >/dev/null; then $sudo_cmd yum install -y $missing
        elif command -v zypper  >/dev/null; then $sudo_cmd zypper --non-interactive install $missing
        elif command -v pacman  >/dev/null; then $sudo_cmd pacman -Sy --noconfirm $missing
        elif command -v apk     >/dev/null; then $sudo_cmd apk add $missing
        else
            echo "No supported package manager found. Install:$missing and re-run." >&2
            exit 1
        fi
    fi

    # Verify rather than trust. A failure inside an && list does not trip set -e, so
    # a package manager that errors out would otherwise let the script sail on and
    # die later at `tmux new` with a far less obvious message.
    for required in curl tmux; do
        if ! command -v "$required" >/dev/null; then
            echo "$required is still missing after the install step - install it and re-run." >&2
            exit 1
        fi
    done

    # First run on a fresh server: fetch the release build for this machine.
    # Later runs skip it - the bot's own self-update owns the binary from then on.
    if [ ! -x ./knopka-groshu ]; then
        case "$(uname -m)" in
            x86_64)        arch=x64 ;;
            aarch64|arm64) arch=arm64 ;;
            *)
                echo "Unsupported architecture $(uname -m) - only x64 and arm64 are published." >&2
                exit 1
                ;;
        esac

        echo "  ↓ Downloading knopka-groshu-linux-$arch ..."
        # Land it under a .part name first: an interrupted transfer must not leave
        # a truncated file that the next run mistakes for an installed binary.
        curl -fL --progress-bar -o knopka-groshu.part \
            "https://github.com/$RELEASES_REPO/releases/latest/download/knopka-groshu-linux-$arch"
        chmod +x knopka-groshu.part
        mv knopka-groshu.part knopka-groshu
        echo
    fi

    # No key handling here: the bot mints its own AES-256 master key into
    # data/master.key on first boot. A .env is only for an operator pinning a
    # specific KG_MASTER_KEY - a migrated database, or a key from a secret store.

    # has-session keeps re-runs idempotent: a second bot on the same SQLite file
    # would fight the single-writer model.
    tmux has-session -t "$SESSION" 2>/dev/null \
        || BOT_DIR="$BOT_DIR" tmux new -d -s "$SESSION" "$SELF"

    exec tmux attach -t "$SESSION"
fi

# Inside the pane: supervise the bot. Guard for the case the outer install block
# never ran - the script invoked from inside an already-open tmux session.
if [ ! -x ./knopka-groshu ]; then
    echo "No knopka-groshu binary in $BOT_DIR." >&2
    echo "Run this script from outside tmux once and it will install one." >&2
    exit 1
fi

# Optional: only present when the operator pins their own KG_MASTER_KEY.
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091  # deployment-local file, not in the repo
    . ./.env
    set +a
fi

# Tells SelfUpdateService a supervisor owns the restart, so it exits clean for
# the loop below instead of prompting for a manual rerun. Only ever set this
# together with the loop - on its own it leaves the bot down after an update.
export INVOCATION_ID=tmux-$SESSION

while :; do
    code=0
    ./knopka-groshu || code=$?
    echo "  ↻ exited ($code) - relaunching in 3s (Ctrl-C to stop)"
    sleep 3
done
