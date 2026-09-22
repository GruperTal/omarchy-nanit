import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

// Mounted once per shell session; bar widgets only render what lives here.
// Camera commands go through bin/nanit (aionanit, one short cloud session per
// call). The stream is different: `nanit stream` prints the RTMPS URL and stays
// up to keep the camera pushing, and a MediaPlayer here plays its audio. Video
// is a second, muted player inside the open panel: Qt's ffmpeg backend ignores
// a video sink attached after playback starts, so the panel makes its own.
QtObject {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "gruper.nanit"
  readonly property string cli: Qt.resolvedUrl("bin/nanit").toString().replace(/^file:\/\//, "")
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy-nanit"

  property var status: null            // last `nanit status` JSON, null until the first fetch
  property bool loggedIn: true         // false once the CLI says it has no session
  property bool listening: false       // always-on audio, persisted across shell restarts
  property bool watching: false        // video wanted while a panel is open
  readonly property bool wanted: listening || watching
  property string url: ""
  readonly property bool busy: cliProcess.running
  readonly property bool live: player.playbackState === MediaPlayer.PlayingState
    && (player.mediaStatus === MediaPlayer.BufferedMedia || player.mediaStatus === MediaPlayer.BufferingMedia)
  readonly property bool connecting: wanted && !live
  property string notice: ""
  property bool noticeIsError: false

  readonly property string name: status && status.name ? status.name : "Nanit"
  readonly property bool light: !!(status && status.light)
  readonly property bool sound: !!(status && status.sound)
  readonly property string climate: status && status.temperature !== null && status.temperature !== undefined
    ? Math.round(status.temperature * 10) / 10 + "° · " + Math.round(status.humidity || 0) + "%" : ""

  function run(args) {
    if (cliProcess.running) return
    notice = ""
    cliProcess.command = [cli].concat(args)
    cliProcess.running = true
  }

  function refresh() { run(["status"]) }
  function setLight(on) { run(["light", on ? "on" : "off"]) }
  function setSound(on) { run(["sound", on ? "on" : "off"]) }
  function toggleLight() { setLight(!light) }
  function toggleSound() { setSound(!sound) }
  function setListening(on) { listening = on === true }
  function toggleListen() { listening = !listening }
  function setWatching(on) { watching = on === true }
  function toggleWatch() { watching = !watching }

  // The external mpv window, for a second screen or a bigger picture.
  function openWindow() { Quickshell.execDetached([cli, "play"]) }

  // Opens a terminal for the one-time venv setup and the MFA login.
  function login() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation",
      shellQuote(cli) + " setup && " + shellQuote(cli) + " login"])
  }

  function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  function elide(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function say(text, isError) {
    notice = text
    noticeIsError = isError === true
    noticeTimer.restart()
  }

  function startStream() { if (!streamProcess.running) streamProcess.running = true }

  function stopStream() {
    player.stop()
    player.source = ""
    url = ""
    if (streamProcess.running) streamProcess.signal(15)
  }

  // Anything that kills the stream ends here: drop it and come back with a fresh URL.
  function restartStream(why) {
    if (!wanted) return
    say("Stream " + why + ", reconnecting…", true)
    stopStream()
    streamRestart.restart()
  }

  onWantedChanged: wanted ? startStream() : stopStream()
  onListeningChanged: listenFile.setText(listening ? "1\n" : "0\n")

  property MediaPlayer player: MediaPlayer {
    audioOutput: AudioOutput {}
    // Audio only here; decoding 1080p nobody looks at is wasted CPU.
    onHasVideoChanged: if (hasVideo) activeVideoTrack = -1
    onErrorOccurred: function(error, message) { root.restartStream("failed (" + root.elide(message) + ")") }
    onMediaStatusChanged: {
      if (mediaStatus === MediaPlayer.EndOfMedia || mediaStatus === MediaPlayer.InvalidMedia) root.restartStream("ended")
    }
  }

  property Process cliProcess: Process {
    stdout: StdioCollector { id: cliOut; waitForEnd: true }
    stderr: StdioCollector { id: cliErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        try { root.status = JSON.parse(cliOut.text); root.loggedIn = true }
        catch (e) { root.say("Bad status from nanit: " + root.elide(cliOut.text), true) }
      } else if (exitCode === 3) {
        root.loggedIn = false
      } else {
        root.say(root.elide(cliErr.text) || "nanit failed", true)
      }
    }
  }

  property Process streamProcess: Process {
    command: [root.cli, "stream"]
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("rtmps://") !== 0) return
        root.url = line.trim()
        root.player.source = root.url
        root.player.play()
      }
    }
    stderr: StdioCollector { id: streamErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 3) { root.loggedIn = false; root.listening = false; root.watching = false; return }
      if (root.wanted) root.restartStream("dropped" + (exitCode !== 0 ? " (" + root.elide(streamErr.text) + ")" : ""))
    }
  }

  // ponytail: flat 5s retry; add backoff if Nanit ever rate-limits us
  property Timer streamRestart: Timer { interval: 5000; onTriggered: if (root.wanted) root.startStream() }
  property Timer noticeTimer: Timer { interval: 8000; onTriggered: root.notice = "" }

  // Survives shell restarts and logins, so "always on" really is.
  property FileView listenFile: FileView {
    path: root.stateDir + "/listen"
    printErrors: false
    onLoaded: root.listening = String(text() || "").trim() === "1"
  }

  // omarchy-shell gruper.nanit toggleListen   (bind it to a key)
  property IpcHandler ipc: IpcHandler {
    target: root.pluginId

    function toggleListen(): void { root.toggleListen() }
    function listen(on: string): void { root.setListening(on === "on" || on === "true" || on === "1") }
    function window(): void { root.openWindow() }
    function light(on: string): void { root.setLight(on === "on" || on === "true" || on === "1") }
    function sound(on: string): void { root.setSound(on === "on" || on === "true" || on === "1") }
    function refresh(): void { root.refresh() }
    function status(): string {
      return JSON.stringify({ listening: root.listening, watching: root.watching, live: root.live, connecting: root.connecting,
        mediaStatus: root.player.mediaStatus, playbackState: root.player.playbackState, error: root.player.errorString,
        activeVideoTrack: root.player.activeVideoTrack, loggedIn: root.loggedIn, camera: root.status })
    }
    function open(): void { if (root.shell) root.shell.summon(root.pluginId, "{}") }
    function close(): void { if (root.shell) root.shell.hide(root.pluginId) }
    function panel(): void { if (root.shell) root.shell.toggle(root.pluginId, "{}") }
  }

  Component.onCompleted: refresh()
}
