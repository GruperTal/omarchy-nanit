import QtQuick
import QtMultimedia
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "gruper.nanit"
  ipcTarget: "gruper.nanit"
  manageIpc: false

  // State lives in the service (one per session); this widget is one per monitor.
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool loggedIn: service ? service.loggedIn : false
  readonly property bool listening: service ? service.listening : false
  readonly property bool watching: service ? service.watching : false
  readonly property bool wanted: service ? service.wanted : false
  readonly property bool windowOpen: service ? service.windowOpen : false
  readonly property bool live: service ? service.live : false
  readonly property bool connecting: service ? service.connecting : false
  readonly property bool busy: service ? service.busy : false
  readonly property bool light: service ? service.light : false
  readonly property bool sound: service ? service.sound : false
  readonly property string name: service ? service.name : "Nanit"
  readonly property string climate: service ? service.climate : ""
  readonly property string notice: service ? service.notice : ""
  readonly property bool noticeIsError: service ? service.noticeIsError : false
  readonly property var status: service ? service.status : null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: bar ? bar.background : Color.background
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: Style.hoverFillFor(foreground, Color.accent)
  readonly property color selectedFill: Style.selectedFillFor(foreground, Color.accent)

  readonly property string statusText: !loggedIn ? "Not logged in"
    : connecting ? "Connecting…"
    : live && listening ? "Listening"
    : live ? "Live"
    : climate !== "" ? climate : "Idle"

  readonly property var rows: !loggedIn ? [
    { key: "login", icon: "󰍂", title: "Log in to Nanit", caption: "Opens a terminal for email, password and the MFA code", toggle: false, checked: false, busy: false }
  ] : [
    { key: "listen", icon: "󰋋", title: "Always-on audio", caption: listening ? (live ? "Playing" : "Connecting…") + " · keeps playing after the panel closes and after a reboot" : "Off", toggle: true, checked: listening, busy: listening && connecting },
    { key: "light", icon: "󰌵", title: "Night light", caption: light ? "On" : "Off", toggle: true, checked: light, busy: busy },
    { key: "sound", icon: "󰎇", title: "White noise", caption: sound ? "Playing" + (status && status.track ? " · " + status.track : "") : "Off", toggle: true, checked: sound, busy: busy }
  ]

  property int cursorIndex: 0
  property bool cursorActive: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function activate(key) {
    if (!service) return
    if (key === "login") service.login()
    else if (key === "listen") service.toggleListen()
    else if (key === "light") service.toggleLight()
    else if (key === "sound") service.toggleSound()
  }

  function cursorKey() {
    return cursorActive && cursorIndex >= 0 && cursorIndex < rows.length ? rows[cursorIndex].key : ""
  }

  function moveCursor(dy) {
    if (rows.length === 0) return
    if (!cursorActive) { cursorActive = true; return }
    cursorIndex = Math.max(0, Math.min(rows.length - 1, cursorIndex + dy))
  }

  onOpenedChanged: {
    if (!service) return
    // The picture is part of the popup: opening it starts the stream, closing
    // it stops it again unless always-on audio keeps it.
    service.setWatching(opened)
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      service.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    dimmed: !root.wanted
    tooltipText: root.name + " · " + root.statusText
    iconComponent: Component {
      Item {
        NanitIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.foreground
          background: root.background
          // Pulses while the stream is being negotiated.
          SequentialAnimation on opacity {
            running: root.connecting
            loops: Animation.Infinite
            onRunningChanged: if (!running) opacity = 1
            NumberAnimation { to: 0.25; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
          }
        }
      }
    }
    onPressed: function(mouseButton) {
      if (!root.service) return
      if (mouseButton === Qt.RightButton) root.service.toggleListen()
      else if (mouseButton === Qt.MiddleButton) root.service.toggleWindow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.loggedIn ? 460 : 340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activate(root.cursorKey())
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (!root.service) return
        if (text === "l") root.service.toggleListen()
        else if (text === "n") root.service.toggleLight()
        else if (text === "s") root.service.toggleSound()
        else if (text === "r") root.service.refresh()
        else if (text === "o") root.service.toggleWindow()
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: root.name
          meta: root.statusText + (root.climate !== "" && root.statusText !== root.climate ? " · " + root.climate : "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.live ? 1.0 : 0.5
          iconComponent: Component {
            NanitIcon {
              iconSize: Style.font.display
              color: root.foreground
              background: Color.popups.background
            }
          }
          trailingControl: Component {
            Row {
              visible: root.loggedIn
              spacing: Style.space(4)
              PanelActionButton {
                iconText: root.windowOpen ? "󰖭" : "󰏌"
                tooltipText: root.windowOpen ? "Close the mpv window" : "Open in a window (o)"
                foreground: root.foreground
                onClicked: if (root.service) root.service.toggleWindow()
              }
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh (r)"
                foreground: root.foreground
                onClicked: if (root.service) root.service.refresh()
              }
            }
          }
        }

        // The picture.
        Rectangle {
          width: parent.width
          height: Math.round(width * 9 / 16)
          visible: root.loggedIn
          color: "black"
          radius: Style.cornerRadius
          clip: true

          // Own muted player, built with its sink attached, torn down on close.
          Loader {
            id: videoLoader
            anchors.fill: parent
            active: root.opened && root.wanted && root.service && root.service.url !== ""
            sourceComponent: Item {
              readonly property bool live: vp.playbackState === MediaPlayer.PlayingState
                && (vp.mediaStatus === MediaPlayer.BufferedMedia || vp.mediaStatus === MediaPlayer.BufferingMedia)
              readonly property string error: vp.errorString
              VideoOutput { id: out; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectFit }
              MediaPlayer {
                id: vp
                source: root.service.url   // a stream restart changes the URL and reloads this too
                videoOutput: out
                audioOutput: AudioOutput { muted: true }
                Component.onCompleted: play()
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: !(videoLoader.item && videoLoader.item.live)
            text: videoLoader.item && videoLoader.item.error !== "" ? "Video failed: " + videoLoader.item.error : "Connecting to " + root.name + "…"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            SequentialAnimation on opacity {
              running: visible
              loops: Animation.Infinite
              NumberAnimation { to: 0.3; duration: 700 }
              NumberAnimation { to: 1.0; duration: 700 }
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        Repeater {
          model: root.rows
          ActionRow {
            required property var modelData
            required property int index
            width: column.width
            row: modelData
            rowIndex: index
          }
        }

        Text {
          width: parent.width
          visible: !root.service
          text: "The plugin service is not running."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.notice !== ""
          text: root.notice
          color: root.noticeIsError ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: line
    required property var row
    required property int rowIndex
    readonly property bool selected: root.cursorActive && root.cursorIndex === rowIndex

    hasCursor: selected
    current: !!row.checked
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: Math.max(labels.implicitHeight, toggle.height) + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.cursorIndex = line.rowIndex }
      onClicked: root.activate(line.row.key)
    }

    Text {
      id: iconText
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.verticalCenter: parent.verticalCenter
      text: line.row.icon
      color: line.row.checked ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
    }

    Column {
      id: labels
      anchors.left: iconText.right
      anchors.leftMargin: Style.space(10)
      anchors.right: toggle.visible ? toggle.left : parent.right
      anchors.rightMargin: Style.spacing.rowPaddingX
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: line.row.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: line.row.caption || ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    ToggleSwitch {
      id: toggle
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.rowPaddingX
      anchors.verticalCenter: parent.verticalCenter
      visible: !!line.row.toggle
      checked: !!line.row.checked
      busy: !!line.row.busy
      hasCursor: line.selected
      foreground: root.foreground
      onToggled: root.activate(line.row.key)
    }
  }
}
