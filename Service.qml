import QtQuick
import Quickshell
import Quickshell.Io

// Mounted once per shell session; bar widgets only render what lives here.
// Everything talks to the camera through bin/nanit (aionanit, one short cloud
// session per call). The audio stream is the exception: `nanit play` stays up
// for as long as mpv does and keeps the camera pushing.
QtObject {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "gruper.nanit"
  readonly property string cli: Qt.resolvedUrl("bin/nanit").toString().replace(/^file:\/\//, "")
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy-nanit"

  property var status: null            // last `nanit status` JSON, null until the first fetch
  property bool loggedIn: true         // false once the CLI says it has no session
  property bool listening: false       // "always on" audio: mpv --no-video, restarted if it dies
  readonly property bool audioUp: listenProcess.running
  readonly property bool watching: watchProcess.running
  readonly property bool busy: cliProcess.running
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

  function watch() {
    if (watchProcess.running) { watchProcess.signal(15); return }
    watchProcess.running = true
  }

  function setListening(on) { listening = on === true }
  function toggleListen() { listening = !listening }

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

  onListeningChanged: {
    listenFile.setText(listening ? "1\n" : "0\n")
    if (listening) { if (!listenProcess.running) listenProcess.running = true }
    else if (listenProcess.running) listenProcess.signal(15)
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

  property Process listenProcess: Process {
    command: [root.cli, "play", "--no-video"]
    stderr: StdioCollector { id: listenErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (!root.listening) return
      if (exitCode === 3) { root.loggedIn = false; root.listening = false; return }
      // ponytail: flat 5s retry; add backoff if Nanit ever rate-limits us
      root.say("Audio stream dropped, reconnecting…" + (exitCode !== 0 ? " (" + root.elide(listenErr.text) + ")" : ""), exitCode !== 0)
      listenRestart.restart()
    }
  }

  property Process watchProcess: Process {
    command: [root.cli, "play"]
    stderr: StdioCollector { id: watchErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 3) root.loggedIn = false
      else if (exitCode !== 0 && exitCode !== 143) root.say(root.elide(watchErr.text) || "mpv exited", true)
    }
  }

  property Timer listenRestart: Timer { interval: 5000; onTriggered: if (root.listening && !listenProcess.running) listenProcess.running = true }
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
    function watch(): void { root.watch() }
    function light(on: string): void { root.setLight(on === "on" || on === "true" || on === "1") }
    function sound(on: string): void { root.setSound(on === "on" || on === "true" || on === "1") }
    function refresh(): void { root.refresh() }
    function status(): string { return JSON.stringify({ listening: root.listening, audioUp: root.audioUp, watching: root.watching, loggedIn: root.loggedIn, camera: root.status }) }
    function open(): void { if (root.shell) root.shell.summon(root.pluginId, "{}") }
    function close(): void { if (root.shell) root.shell.hide(root.pluginId) }
    function panel(): void { if (root.shell) root.shell.toggle(root.pluginId, "{}") }
  }

  Component.onCompleted: refresh()
}
