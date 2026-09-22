import QtQuick
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
  readonly property bool audioUp: service ? service.audioUp : false
  readonly property bool watching: service ? service.watching : false
  readonly property bool busy: service ? service.busy : false
  readonly property bool light: service ? service.light : false
  readonly property bool sound: service ? service.sound : false
  readonly property string name: service ? service.name : "Nanit"
  readonly property string climate: service ? service.climate : ""
  readonly property string notice: service ? service.notice : ""
  readonly property bool noticeIsError: service ? service.noticeIsError : false
  readonly property var status: service ? service.status : null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: Style.hoverFillFor(foreground, Color.accent)
  readonly property color selectedFill: Style.selectedFillFor(foreground, Color.accent)

  readonly property string icon: "󰹼"
  readonly property string statusText: !loggedIn ? "Not logged in"
    : watching && audioUp ? "Watching · Listening"
    : watching ? "Watching"
    : audioUp ? "Listening"
    : listening ? "Reconnecting audio…"
    : climate !== "" ? climate : "Idle"

  readonly property var rows: !loggedIn ? [
    { key: "login", icon: "󰍂", title: "Log in to Nanit", caption: "Opens a terminal for email, password and the MFA code", toggle: false, checked: false, busy: false }
  ] : [
    { key: "watch", icon: "󰕧", title: "Watch", caption: watching ? "Video window open · click to close" : "Open the camera in an mpv window", toggle: false, checked: watching, busy: false },
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
    else if (key === "watch") service.watch()
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
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      if (service) service.refresh()
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    fontSize: Style.bar.iconFont
    dimmed: !root.audioUp && !root.watching
    tooltipText: root.name + " · " + root.statusText
    onPressed: function(mouseButton) {
      if (!root.service) return
      if (mouseButton === Qt.RightButton) root.service.toggleListen()
      else if (mouseButton === Qt.MiddleButton) root.service.watch()
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

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
        else if (text === "w") root.service.watch()
        else if (text === "n") root.service.toggleLight()
        else if (text === "s") root.service.toggleSound()
        else if (text === "r") root.service.refresh()
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: root.name
          meta: root.statusText
          detail: root.loggedIn ? "Always-on audio" : ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.audioUp || root.watching ? 1.0 : 0.5
          iconComponent: Component {
            Text {
              text: root.icon
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          // The headline feature: audio keeps playing while you work, and comes back after a reboot.
          trailingControl: Component {
            ToggleSwitch {
              visible: root.loggedIn
              checked: root.listening
              busy: root.listening && !root.audioUp
              foreground: root.foreground
              onToggled: if (root.service) root.service.toggleListen()
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
        height: visible ? implicitHeight : 0
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
