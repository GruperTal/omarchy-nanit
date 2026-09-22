#!/usr/bin/env python3
"""Nanit camera CLI for the Omarchy plugin. Every call is one short cloud session.

  nanit login              email / password / MFA in a terminal, saves the session
  nanit status             JSON: light, sound, volume, temperature, humidity
  nanit light on|off       night light
  nanit sound on|off       white noise from the camera speaker
  nanit volume 0-100       camera speaker volume
  nanit play [--no-video]  stream to mpv; keeps the camera pushing until mpv exits
"""

import asyncio
import ctypes
import json
import logging
import os
import signal
import sys
from getpass import getpass
from pathlib import Path

import aiohttp
from aionanit import NanitAuthError, NanitClient, NanitMfaRequiredError
from aionanit.models import NightLightState

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "omarchy-nanit"
SESSION = STATE_DIR / "session.json"
KEEPALIVE = 5 * 60  # the camera stops pushing ~20 min after the last PUT_STREAMING


def save(data):
    # ponytail: 0600 file, not the keyring; move to secret-tool if that ever matters
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    SESSION.touch(mode=0o600)
    SESSION.chmod(0o600)
    SESSION.write_text(json.dumps(data, indent=2) + "\n")


async def login():
    email = input("Nanit email: ").strip()
    password = getpass("Password: ")
    async with aiohttp.ClientSession() as http:
        client = NanitClient(http)
        try:
            tokens = await client.async_login(email, password)
        except NanitMfaRequiredError as err:
            code = input("MFA code (check your phone/email): ").strip()
            tokens = await client.async_verify_mfa(email, password, err.mfa_token, code)
        baby = next((b for b in await client.async_get_babies() if b.camera_uid), None)
        if baby is None:
            sys.exit("No camera found on this account")
        save({**tokens, "baby_uid": baby.uid, "camera_uid": baby.camera_uid, "name": baby.name})
        print(f"Logged in. Camera: {baby.name}")


async def session(fn):
    """Restore the saved session, connect to the camera, run fn(camera)."""
    if not SESSION.exists():
        print("Not logged in", file=sys.stderr)
        sys.exit(3)
    data = json.loads(SESSION.read_text())
    async with aiohttp.ClientSession() as http:
        client = NanitClient(http)
        client.restore_tokens(data["access_token"], data["refresh_token"])
        # restore_tokens forces a refresh on first use; trust the JWT's own expiry instead.
        await client.token_manager.update_tokens(data["access_token"], data["refresh_token"])
        # ponytail: last writer wins when two calls refresh at once; fine for hourly rotation
        client.token_manager.on_tokens_refreshed(
            lambda a, r: save({**data, "access_token": a, "refresh_token": r}))
        camera = client.camera(data["camera_uid"], data["baby_uid"])
        try:
            await camera.async_start()
            return await fn(camera)
        finally:
            await client.async_close()


async def status(camera):
    s = camera.state
    print(json.dumps({
        "name": json.loads(SESSION.read_text()).get("name", "Nanit"),
        "light": s.control.night_light == NightLightState.ON,
        "sound": s.playback.playing,
        "track": s.playback.current_track,
        "volume": s.settings.volume,
        "temperature": s.sensors.temperature,
        "humidity": s.sensors.humidity,
        "night": s.sensors.night,
        "transport": s.connection.transport.name.lower(),
    }))


async def light(camera, on):
    await camera.async_set_control(night_light=NightLightState.ON if on else NightLightState.OFF)
    await status(camera)


async def sound(camera, on):
    await (camera.async_start_playback() if on else camera.async_stop_playback())
    await status(camera)


async def volume(camera, level):
    await camera.async_set_settings(volume=level)
    await status(camera)


async def play(camera, no_video):
    url = await camera.async_get_stream_rtmps_url()
    await camera.async_start_streaming(rtmps_url=url)
    name = json.loads(SESSION.read_text()).get("name", "Nanit")
    args = ["mpv", "--profile=low-latency", "--really-quiet", f"--title=Nanit · {name}"]
    if no_video:
        args.append("--no-video")
    libc = ctypes.CDLL("libc.so.6")
    # PR_SET_PDEATHSIG: mpv dies with us even if we get SIGKILLed.
    proc = await asyncio.create_subprocess_exec(*args, url, preexec_fn=lambda: libc.prctl(1, signal.SIGTERM))
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, proc.terminate)
    while proc.returncode is None:
        try:
            await asyncio.wait_for(asyncio.shield(proc.wait()), KEEPALIVE)
        except TimeoutError:
            try:
                await camera.async_start_streaming(rtmps_url=url, reconnect_on_failure=False)
            except Exception as err:  # noqa: BLE001 - keepalive is best effort; mpv decides when we are done
                logging.warning("keepalive failed: %s", err)
    # ponytail: no async_stop_streaming: it shares the MOBILE stream id with the phone app
    # and would cut a stream someone else is watching. The camera lapses on its own.
    return 0 if proc.returncode in (0, -signal.SIGTERM) else proc.returncode


def main(argv):
    logging.basicConfig(level=logging.WARNING, format="%(message)s")
    cmd, *rest = argv or ["help"]
    onoff = {"on": True, "off": False}
    try:
        if cmd == "login":
            return asyncio.run(login())
        if cmd == "status":
            return asyncio.run(session(status))
        if cmd == "light" and rest and rest[0] in onoff:
            return asyncio.run(session(lambda c: light(c, onoff[rest[0]])))
        if cmd == "sound" and rest and rest[0] in onoff:
            return asyncio.run(session(lambda c: sound(c, onoff[rest[0]])))
        if cmd == "volume" and rest and rest[0].isdigit():
            return asyncio.run(session(lambda c: volume(c, int(rest[0]))))
        if cmd == "play":
            return asyncio.run(session(lambda c: play(c, "--no-video" in rest)))
    except NanitAuthError as err:
        print(f"Not logged in ({err})", file=sys.stderr)
        return 3
    print(__doc__.strip())
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
