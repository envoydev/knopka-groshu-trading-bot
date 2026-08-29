# Knopka Groshu

A self-hosted hedged-grid scalping bot for BingX and Binance USDT-margined
perpetual futures. One self-contained binary, a console dashboard, and an
optional Telegram control surface - no .NET runtime to install.

This repository distributes the release binaries only. The source is private.

## Install and run

### Linux

One script does everything: installs `curl` and `tmux` if missing, downloads the
right binary, generates your encryption key, and starts the bot in a detachable
session.

```bash
mkdir -p ~/knopka-groshu && cd ~/knopka-groshu

curl -fL -O https://github.com/envoydev/knopka-groshu-trading-bot/releases/latest/download/run_linux.sh
chmod +x run_linux.sh
./run_linux.sh
```

Re-run `./run_linux.sh` any time - it starts the bot or reattaches to the
running one, so it is your everyday start command.

Install somewhere else with `BOT_DIR`:

```bash
BOT_DIR=/opt/knopka-groshu ./run_linux.sh
```

Tested on Debian and Ubuntu; the dependency step uses `apt` and needs `sudo`. On
other distributions install `curl` and `tmux` yourself first - the script then
skips that step.

### Windows

```powershell
mkdir ~\knopka-groshu; cd ~\knopka-groshu
Invoke-WebRequest -UseBasicParsing -OutFile run_windows.ps1 `
  https://github.com/envoydev/knopka-groshu-trading-bot/releases/latest/download/run_windows.ps1
.\run_windows.ps1
```

If PowerShell refuses to run it, allow local scripts once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Closing the window stops the bot. To keep it running unattended, register it as
a Windows Service (NSSM, `sc.exe`) or a Scheduled Task set to *Run whether user
is logged on or not*.

## First run - what to set up

Everything is configured from the menu. There is no config file and no
environment variables to set.

1. **Account Settings → Add Exchange Account** - your BingX or Binance API key
   and secret. Stored encrypted; needed before anything trades.
2. **Account Settings → Edit Telegram** - bot token and your chat ID, if you
   want the Telegram surface. Optional.
3. **Campaigns → New Campaign** - pick a symbol and its settings. This is what
   actually trades.

Then watch **Statistics** and **Live Orders**, and use **Bot Maintenance** for
updates and logs.

## Everyday commands (Linux)

| Action                | How                                                 |
|-----------------------|-----------------------------------------------------|
| Start or reattach     | `./run_linux.sh`                                    |
| Detach, leave running | `Ctrl-b` then `d`                                   |
| Attach by name        | `tmux attach -t knopka-groshu`                      |
| Stop it (graceful)    | `Ctrl-C`, then `Ctrl-C` again within 3 seconds      |
| Force stop            | `tmux kill-session -t knopka-groshu`                |
| Is it running?        | `tmux ls`                                           |
| Scroll back           | `Ctrl-b` then `[`, arrows, `q` to exit              |

Stopping takes two `Ctrl-C` presses because the launcher supervises the bot: the
first shuts the bot down, the second stops the launcher before it relaunches.

```bash
tmux kill-session -t knopka-groshu
```

That kills the session and everything inside it immediately - no graceful
shutdown, no chance to finish database writes or close exchange connections.
Use it when the bot is wedged, not as your routine stop.

The session does not survive a reboot. To bring it back automatically, add this
with `crontab -e`:

```text
@reboot cd $HOME/knopka-groshu && ./run_linux.sh
```

Detailed walkthrough, including troubleshooting: [tmux guide](tmux-guide.md).

## Your encryption key

Exchange API keys and the Telegram token are encrypted with AES-256-GCM in the
local database. The bot generates the key on first boot and writes it to
`data/master.key` - you never create or enter it.

- **Back up the whole `data/` folder.** Key and database both live there. Lose
  `master.key` and the stored credentials cannot be decrypted.
- **Moving machines:** copy `data/` across intact. The bot refuses to start on a
  database with no matching key rather than orphaning your credentials.
- **Never share it.** Anyone holding `data/` can decrypt your credentials.

To pin your own key instead, set `KG_MASTER_KEY` to its base64 value. It wins
over the key file. On Linux a `.env` next to the binary works too - the launcher
sources it when present.

## Where your data lives

```text
knopka-groshu/
├── knopka-groshu        the binary
├── run_linux.sh         the launcher (Linux only)
└── data/
    ├── knopka-groshu.db the SQLite database
    ├── master.key       the encryption key, owner-readable only
    └── logs/            rolling application and per-symbol logs
```

Read the log without attaching:

```bash
tail -50 ~/knopka-groshu/data/logs/app-*.log
```

## Updating

**Bot Maintenance → Update** in either surface downloads the right asset, swaps
the binary and restarts. On Linux the launcher brings it straight back; on
Windows it exits and asks you to rerun the executable.

To update by hand, replace the binary while the bot is stopped.

## Downloads

The launcher for your platform is all you need - it picks and downloads the
right binary. Raw binaries are listed for manual installs.

| Platform            | Asset                         |
|---------------------|-------------------------------|
| Linux, any          | `run_linux.sh`                |
| Windows, any        | `run_windows.ps1`             |
| Linux, Intel/AMD    | `knopka-groshu-linux-x64`     |
| Linux, ARM          | `knopka-groshu-linux-arm64`   |
| Windows, Intel/AMD  | `knopka-groshu-win-x64.exe`   |
| Windows, ARM        | `knopka-groshu-win-arm64.exe` |

All assets: [latest release](https://github.com/envoydev/knopka-groshu-trading-bot/releases/latest).

## Requirements

- A 64-bit Linux or Windows machine. No .NET runtime needed.
- Outbound HTTPS to your exchange, to Telegram if you use it, and to GitHub for
  update checks.
- A writable home directory - the binary unpacks native dependencies into a
  per-user cache on first run, which is why the first launch is slower.

## Довідник меню (українською)

Пояснення кожного екрана Telegram-бота - куди веде кожен пункт, що означають
налаштування бота й кампанії: [довідник меню](telegram-menu-uk.html).
Відкрийте у браузері; щоб зберегти PDF - друк у файл.
