# Nanit — Omarchy plugin

Your Nanit baby monitor in the Omarchy bar. Click the Nanit mark to see the
camera right in the popup, keep its audio playing while you work ("always-on"
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
| Bar icon, middle click | open (or close) the external mpv window |
| Popup | shows the camera with sound for as long as it is open |
| Pop-out button (header) | one mpv window, shown immediately while it connects; click again to close it. The in-popup audio mutes while it is open |
| Always-on audio | keeps playing after the popup closes and after a reboot; the bar icon pulses while it connects |
| Night light | camera night light |
| White noise | the camera's own sound machine |

Keys inside the panel: `j`/`k` move, `enter` activate, `l` listen,
`n` night light, `s` sound, `r` refresh, `o` mpv window, `esc` close.

IPC, for keybindings:

```bash
omarchy-shell gruper.nanit toggleListen
omarchy-shell gruper.nanit listen on
omarchy-shell gruper.nanit light on
omarchy-shell gruper.nanit sound off
omarchy-shell gruper.nanit window
omarchy-shell gruper.nanit status
```

The CLI works on its own too: `bin/nanit status|light|sound|volume|stream|play`.

## How the stream works

The camera pushes RTMPS only while asked. `nanit stream` sends the start
request, prints the URL, and re-sends the request every five minutes until it
is killed (the camera lapses about 20 minutes after the last request). The
service plays that URL with Qt Multimedia for audio; the popup opens a second,
muted player for the picture, because Qt's ffmpeg backend ignores a video sink
attached after playback has started. If the stream drops, everything restarts
with a fresh URL after five seconds.

Do not pass mpv `--profile=low-latency` on this stream: it stops probing
before the AAC track shows up and you get silent video.

## Hacking

Omarchy caches plugin QML, so after editing run `omarchy restart shell`.
