# Nanit — Omarchy plugin

Your Nanit baby monitor in the Omarchy bar. Click the baby face to open the
camera in an mpv window, keep its audio playing while you work ("always-on"
audio that comes back after a reboot), and toggle the night light and the
camera's white noise. Temperature and humidity show in the panel.

It talks to the Nanit cloud directly through [`aionanit`](https://github.com/wealthystudent/ha-nanit),
the library behind the Home Assistant integration. No Home Assistant needed.

## Requirements

- Omarchy 4 (the Quickshell-based `omarchy-shell`)
- `mpv` (ships with Omarchy) and `python3`
- A Nanit account with a camera

## Install

```bash
omarchy plugin add https://github.com/GruperTal/omarchy-nanit.git --enable
omarchy bar move gruper.nanit --before omarchy.bluetooth
```

Then click the icon and choose **Log in to Nanit**. That opens a terminal,
builds a private Python venv with `aionanit` under
`~/.local/share/omarchy-nanit/`, and asks for your email, password and the MFA
code Nanit sends you. The session lands in `~/.local/state/omarchy-nanit/session.json`
(mode 0600) and refreshes itself from then on.

## Use

| Where | Action |
|---|---|
| Bar icon, left click | open the panel |
| Bar icon, right click | toggle always-on audio |
| Bar icon, middle click | open the video window |
| Panel switch (top) | always-on audio: `mpv --no-video`, restarted if the stream drops, persisted across shell restarts |
| Watch | video window; click again to close it |
| Night light | camera night light |
| White noise | the camera's own sound machine |

Keys inside the panel: `j`/`k` move, `enter` activate, `l` listen, `w` watch,
`n` night light, `s` sound, `r` refresh, `esc` close.

IPC, for keybindings:

```bash
omarchy-shell gruper.nanit toggleListen
omarchy-shell gruper.nanit watch
omarchy-shell gruper.nanit light on
omarchy-shell gruper.nanit sound off
omarchy-shell gruper.nanit status
```

The CLI works on its own too: `bin/nanit status|light|sound|volume|play`.

## How the stream stays up

The camera pushes RTMPS only while asked. `nanit play` sends the start
request, launches mpv, and re-sends it every five minutes until mpv exits
(the camera lapses about 20 minutes after the last request). If the stream
still drops, the service restarts the whole thing after five seconds.
