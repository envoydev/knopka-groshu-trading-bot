# Running the bot with tmux

The bot needs a terminal to show its dashboard, but an SSH session ends when you close
your laptop. tmux solves that: it holds the terminal open on the server, and you attach
to it or leave it whenever you like. `run_linux.sh` sets this up for you.

Your session is called **`knopka-groshu`**. Everything below assumes the bot was
installed with `run_linux.sh`.

## The five commands you actually need

| Goal | Command |
|------|---------|
| Start the bot | `cd /home/knopka-groshu && ./run_linux.sh` |
| Leave it running, return to your shell | `Ctrl-b` then `d` |
| Come back to it | `./run_linux.sh` (or `tmux attach -t knopka-groshu`) |
| Stop it | `Ctrl-C`, then `Ctrl-C` again during the countdown |
| Check whether it is alive | `tmux ls` |

`Ctrl-b` is tmux's prefix key: press `Ctrl-b`, release both, then press the next key.
It is not a combination like `Ctrl-Alt-Del`.

## Starting and returning

The launcher is safe to run any number of times. The first run installs what is
missing, downloads the binary and starts the bot; later runs just reattach to the
session that is already there.

```bash
cd /home/knopka-groshu
./run_linux.sh
```

So you never need to remember whether the bot is running - run the script and you will
either start it or land back in it.

## Leaving without stopping

Press `Ctrl-b`, then `d` (for *detach*). You are back at your shell prompt and the bot
carries on trading. You can close the SSH connection entirely; it keeps running.

**Closing your terminal without detaching is also safe.** tmux keeps the session alive
regardless. Detaching is just tidier.

## Stopping - it takes two Ctrl-Cs

The launcher supervises the bot: when the bot exits, it starts it again. That is what
makes self-updates seamless, and it is why stopping takes two presses.

1. **First `Ctrl-C`** - the bot shuts down gracefully, finishing its database writes and
   closing its exchange connections properly.
2. The launcher prints `↻ exited (0) - relaunching in 3s (Ctrl-C to stop)`.
3. **Second `Ctrl-C`, within those three seconds** - stops the launcher too. The session
   closes and you are back at your shell.

Miss the three-second window and the bot starts again. That is not a fault - press
`Ctrl-C` twice more.

**Quitting from the bot's own menu does not stop it.** The bot exits the same way after
a normal quit as after a self-update, so the launcher cannot tell the difference and
brings it back. Use `Ctrl-C`.

## Stopping from outside, without attaching

Send the same two presses into the session remotely:

```bash
tmux send-keys -t knopka-groshu C-c
sleep 2
tmux send-keys -t knopka-groshu C-c
```

Or stop the supervisor first, then the bot:

```bash
pgrep -af run_linux.sh          # see what you are about to stop
pkill -f run_linux.sh           # supervisor gone - nothing will relaunch
pkill -INT -x knopka-groshu     # graceful shutdown
```

Then confirm:

```bash
tmux ls                              # session should be gone
pgrep -x knopka-groshu || echo "bot stopped"
```

## Restarting

```bash
cd /home/knopka-groshu && ./run_linux.sh
```

There is no separate restart command - starting and reattaching are the same action.

## Reading the screen

| Goal | Keys |
|------|------|
| Scroll back through output | `Ctrl-b` then `[`, then arrows or PgUp |
| Leave scroll mode | `q` |
| Search the scrollback | `Ctrl-b` then `[`, then `Ctrl-s`, type, Enter |

You must leave scroll mode before the dashboard responds to keys again. If the bot seems
frozen, press `q` first - you are probably still scrolling.

## What you will see when the bot updates itself

Two different things happen, and they look different on screen.

**A settings change** - after you change API keys or Telegram settings from the menu, the
bot restarts itself in place. Same session, same window; you just see it start up again.

**A version update** - the bot downloads the new version, replaces itself and exits. The
launcher prints its countdown and starts the new version. You will see:

```text
✅ Update applied. Restarting on v1.0.3.660
  ↻ exited (0) - relaunching in 3s (Ctrl-C to stop)
```

Nothing to do; it comes back on its own. You do not need to be attached for either.

## After a server reboot

**The session does not survive a reboot.** tmux runs in memory. After the server comes
back you must start the bot again:

```bash
cd /home/knopka-groshu && ./run_linux.sh
```

To have it start automatically, add this line with `crontab -e`:

```text
@reboot cd $HOME/knopka-groshu && ./run_linux.sh
```

## When something looks wrong

**`tmux ls` says "no server running"** - no session exists, so the bot is not running.
Start it with `./run_linux.sh`.

**`./run_linux.sh` says the binary is missing** - you are in the wrong folder, or the
download failed. `cd /home/knopka-groshu` first. To force a fresh download, delete the
binary and run the script again:

```bash
rm -f knopka-groshu && ./run_linux.sh
```

**The bot keeps restarting in a loop** - it is failing at startup. Attach and read the
error above the `↻ exited` line, or check the log:

```bash
tail -50 /home/knopka-groshu/data/logs/app-*.log
```

Press `Ctrl-C` twice to stop the loop while you investigate.

**You see two sessions in `tmux ls`** - stop one immediately. Two bots on one database
will corrupt it; SQLite allows a single writer, and both will be trading the same
accounts. Kill the extra one:

```bash
tmux kill-session -t <the-extra-name>
```

The launcher will not create a second session by itself - it checks first - so this only
happens if a session was started by hand under another name.

## Things not to do

**Do not use `kill -9`.** It stops the bot instantly with no chance to finish database
writes or close exchange connections cleanly. Use `Ctrl-C`, or `pkill -INT` as shown
above.

**Do not run a second copy in another folder against the same data.** The database takes
one writer. Two bots means corruption and duplicate orders.

**`tmux kill-session` is a last resort.** It is a hard stop with no graceful shutdown -
appropriate when the bot is genuinely wedged, wrong as a routine way to stop it.

## tmux commands worth knowing

| Command | What it does |
|---------|--------------|
| `tmux ls` | List sessions |
| `tmux attach -t knopka-groshu` | Attach by name |
| `tmux kill-session -t knopka-groshu` | Hard stop - see the warning above |
| `Ctrl-b` `d` | Detach |
| `Ctrl-b` `[` | Scroll mode (`q` leaves) |
| `Ctrl-b` `?` | Full key list (`q` leaves) |
