# powerbutton-guard

**Stop your Linux box from shutting down the instant you brush the power button.**

By default `systemd-logind` ships with `HandlePowerKey=poweroff`. That means a
single, brief, accidental touch (a sleeve, a cable, a cat) powers the machine
off immediately, with no confirmation and no way to take it back.

`powerbutton-guard` takes the button away from logind and requires a deliberate
gesture instead.

| You do | It does |
|---|---|
| **One press** | Blinks a keyboard LED, prints a message, arms for 2s, then quietly disarms. **Nothing happens.** |
| **Two presses** within the window | Starts a shutdown with **1 minute of cancellable grace** |
| **Press during the countdown** | **Cancels** the shutdown |
| `sudo shutdown -c` from anywhere | Also cancels it |

Every timing is configurable.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/kreuzhofer/powerbutton-guard/main/install.sh | sudo bash
```

That's it. The installer is idempotent, keeps any config you've already edited,
and verifies the service is running before it reports success.

<details>
<summary>Prefer to read it first? (you should)</summary>

```sh
git clone https://github.com/kreuzhofer/powerbutton-guard
cd powerbutton-guard
less install.sh
sudo ./install.sh          # installs from the checkout, no downloads
```
</details>

## Why the feedback isn't a beep

The obvious design is "beep to confirm". On a lot of modern hardware that
silently does nothing.

This project came out of a mini PC with **no working audio output
of any kind**: no piezo buzzer on the board, nothing plugged into the analog
jack, and an HDMI monitor with no speakers. Note that the `pcspkr` driver
loading successfully proves nothing; `/sys/devices/platform/pcspkr` and the
legacy `isa0061` port exist on essentially every x86 board whether or not a
buzzer is physically soldered on. Most distros blacklist the module anyway.

So feedback here is **visual and remote**, on three independent channels, none
of which is required to succeed:

- a **keyboard LED** (scroll lock by default, because nothing else uses it, so a blink
  can't be confused with a real caps/num lock change)
- a message on the **console TTY**, visible on an attached monitor
- **`wall`**, so any SSH session sees it too

## Configuration

Edit `/etc/default/powerbutton-guard`, then
`sudo systemctl restart powerbutton-guard`.

| Setting | Default | Meaning |
|---|---|---|
| `ARM_WINDOW` | `2.0` | Seconds allowed between the first and second press |
| `GRACE_MINUTES` | `1` | Cancellable minutes before power actually goes off |
| `LED_PATH` | `auto` | `auto`, `none`, or an explicit `/sys/class/leds/<name>/brightness` |
| `NOTIFY_TTY` | `/dev/tty1` | Console to write to, or `none`. `wall` is always used as well |

Watch it live:

```sh
journalctl -u powerbutton-guard -f
```

## How it works

- **`/etc/systemd/logind.conf.d/10-powerbutton.conf`** sets `HandlePowerKey=ignore`
  and `HandlePowerKeyLongPress=ignore`, so logind opens the button device but
  never acts on it.
- **`/usr/local/sbin/powerbutton-guard`** reads `KEY_POWER` events directly from
  every `/dev/input/event*` named `Power Button` and implements the pattern.

Two details that matter more than they look:

**It reads every matching device, with a 400 ms debounce.** ACPI commonly
exposes *two* power buttons (`LNXPWRBN` the fixed-feature button and `PNP0C0C`
the control-method one). Without debouncing, one physical press can arrive on
both and count as a double-press, turning the guard into an instant-shutdown
button, the exact bug it exists to prevent.

**Pending-shutdown state is read from `/run/systemd/shutdown/scheduled` on every
press, never cached.** An earlier version kept a boolean. Cancel a countdown
over SSH with `shutdown -c` and that boolean went stale, so the next button
press was silently swallowed as a redundant cancel instead of arming. Ask the
system, don't remember.

### Why not just `HandlePowerKeyLongPress`?

systemd 249+ offers `HandlePowerKeyLongPress=poweroff`, which sounds like it
solves this without any extra software. In practice it's a race you often lose:
systemd's long-press threshold is a hardcoded **5 seconds**, while firmware ACPI
override is typically **4 seconds**. On many boards the firmware cuts power
first: an unclean yank rather than a clean shutdown. A double-press sidesteps
the whole problem.

## Requirements

- systemd (tested on 255 / Ubuntu 24.04)
- `python3`, standard library only, no `python-evdev` or other dependencies
- root, for `/dev/input` access and to call `shutdown`

## Uninstalling

```sh
curl -fsSL https://raw.githubusercontent.com/kreuzhofer/powerbutton-guard/main/uninstall.sh | sudo bash
```

Your `/etc/default/powerbutton-guard` is deliberately left in place so a
reinstall picks your settings back up; delete it by hand if you want it gone.

> **Note:** uninstalling restores the systemd default, so a single short press
> will power the machine off immediately again.

## A word of caution

If the daemon isn't running, the button does **nothing at all**. That's the
safe failure mode, but it does mean you can't power the machine down from the
front panel without holding the button for a firmware-level hard cut (~4s,
unclean). Keep another way in, and test the pattern before you rely on it.

## License

MIT. See [LICENSE](LICENSE).
