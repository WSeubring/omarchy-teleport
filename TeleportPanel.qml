import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "wseubring.teleport"
  ipcTarget: "wseubring.teleport"
  manageIpc: false

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
  readonly property int refreshIntervalSec: Math.max(5, setting("refreshIntervalSec", 30))

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Bar label: the active kube cluster; icon only while logged out.
  readonly property string barLabel: teleport.cluster !== "" ? teleport.cluster : "no cluster"

  // Cursor: "clusters" rows only; the hero row owns no cursor target.
  property int clusterIndex: 0
  property bool cursorActive: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    clusterIndex = Math.max(0, indexOfSelected())
    if (panelFlick) panelFlick.contentY = 0
    teleport.refresh()
    teleport.refreshClusters()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function indexOfSelected() {
    for (var i = 0; i < teleport.clusters.length; i++) {
      if (teleport.clusters[i].name === teleport.cluster) return i
    }
    return 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0 || teleport.clusters.length === 0) return
    clusterIndex = Math.max(0, Math.min(teleport.clusters.length - 1, clusterIndex + dy))
    scrollCursorIntoView()
  }

  function activateCursor() {
    if (teleport.clusters.length === 0) return
    var entry = teleport.clusters[clusterIndex]
    if (entry) teleport.selectCluster(entry.name)
  }

  function setClusterCursor(index) {
    cursorActive = true
    clusterIndex = index
  }

  function scrollCursorIntoView() {
    if (!panelFlick || !clusterColumn) return
    var item = clusterColumn.children[clusterIndex]
    if (!item) return
    Qt.callLater(function () {
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  TeleportService {
    id: teleport
    settings: root.settings
    pluginDir: root.pluginDir
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { teleport.refresh(); teleport.refreshClusters(); return "ok" }
    function login(): string { teleport.login(); return "ok" }
    function status(): string { return teleport.sessionState + " " + teleport.cluster }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: teleport.refresh()
  }

  // Drives the "3h 12m left" countdown and the near-expiry bar warning.
  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: teleport.nowEpoch = Math.floor(Date.now() / 1000)
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical || !teleport.active
      ? "󱃾"
      : "󱃾  " + root.barLabel + (teleport.onProduction ? "  󰀦" : "")
    labelVisible: !teleport.loggingIn
    // Urgent while on a production cluster, or when the session runs out.
    active: teleport.expiringSoon || teleport.onProduction
    dimmed: !teleport.active && !teleport.busy
    fontSize: Style.font.caption
    tooltipText: teleport.loggingIn
      ? "Teleport: " + (teleport.actionStatus !== "" ? teleport.actionStatus : "Working…")
      : teleport.active
        ? (teleport.onProduction ? "Teleport: PRODUCTION — " : "Teleport: ")
          + root.barLabel + " · " + teleport.remainingText
        : "Teleport: not logged in — click to log in"
    onPressed: function (b) {
      if (b === Qt.RightButton) { teleport.refresh(); teleport.refreshClusters() }
      else if (b === Qt.MiddleButton) teleport.copyText(teleport.cluster)
      else if (!teleport.active) teleport.login()
      else root.toggle()
    }

    Spinner {
      anchors.centerIn: parent
      running: teleport.loggingIn
      color: button.active ? root.urgent : root.foreground
      fontSize: Style.font.caption
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = t.toLowerCase()
        if (key === "r") { teleport.refresh(); teleport.refreshClusters() }
        else if (key === "l") teleport.login()
        else if (key === "o") teleport.logout()
        else if (key === "c") teleport.copyText(teleport.cluster)
        else if (key === "y") teleport.copyText(teleport.proxy)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: teleport.cluster !== "" ? teleport.cluster : "Teleport"
            meta: teleport.user === ""
              ? "Not logged in"
              : (teleport.onProduction ? "PRODUCTION · " : "") + teleport.user + " @ " + teleport.proxy
            detail: teleport.active ? teleport.remainingText : "session expired"
            foreground: teleport.active && !teleport.onProduction ? root.foreground : root.urgent
            fontFamily: root.fontFamily
            iconComponent: Component {
              Item {
                implicitWidth: heroIcon.implicitWidth
                implicitHeight: heroIcon.implicitHeight

                Text {
                  id: heroIcon
                  visible: !teleport.loggingIn
                  text: teleport.onProduction ? "󰀦" : "󱃾"
                  color: teleport.active && !teleport.onProduction ? root.foreground : root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }

                Spinner {
                  anchors.centerIn: heroIcon
                  running: teleport.loggingIn
                  color: teleport.active && !teleport.onProduction ? root.foreground : root.urgent
                  fontSize: Style.font.display
                }
              }
            }

            trailingControl: Component {
              Row {
                spacing: Style.space(4)

                PanelActionButton {
                  iconText: "󰌋"
                  tooltipText: "Renew session (l)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !teleport.busy
                  onClicked: teleport.login()
                }

                PanelActionButton {
                  iconText: "󰅖"
                  tooltipText: "Log out (o)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !teleport.busy && teleport.sessionState !== "off"
                  onClicked: teleport.logout()
                }

                PanelActionButton {
                  iconText: "󰑐"
                  tooltipText: "Refresh (r)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !teleport.clustersLoading
                  onClicked: { teleport.refresh(); teleport.refreshClusters() }
                }
              }
            }
          }

          Text {
            visible: teleport.actionStatus !== "" || teleport.lastError !== ""
            width: parent.width
            text: teleport.actionStatus !== "" ? teleport.actionStatus : teleport.lastError
            color: teleport.actionStatus !== "" ? root.dim : root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair { label: "Proxy"; value: teleport.proxy }
            InfoPair { label: "User"; value: teleport.user }
            InfoPair { label: "Valid until"; value: teleport.validUntil.replace(/ \[.*\]/, "") }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "KUBERNETES CLUSTERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: teleport.clusters.length === 0
              width: parent.width
              text: teleport.clustersLoading ? "Loading clusters…" : "No clusters available."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: clusterColumn
              visible: teleport.clusters.length > 0
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: teleport.clusters
                ClusterRow {
                  required property var modelData
                  required property int index
                  width: clusterColumn.width
                  entry: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  // Shared loading glyph: hidden unless running, so no stray rotating
  // character is left behind once the action finishes.
  component Spinner: Text {
    id: spinner
    property bool running: false
    property real fontSize: Style.font.body

    visible: running
    text: "󰦖"
    font.family: root.fontFamily
    font.pixelSize: fontSize
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    RotationAnimator on rotation {
      running: spinner.running
      from: 0; to: 360
      duration: 800
      loops: Animation.Infinite
    }
  }

  component ClusterRow: CursorSurface {
    id: clusterRow
    property var entry: null
    property int rowIndex: 0
    readonly property string name: entry ? String(entry.name || "") : ""
    readonly property string labels: entry ? String(entry.labels || "") : ""
    readonly property bool isCurrent: name !== "" && name === teleport.cluster
    readonly property bool isProduction: teleport.isProduction(name)
    readonly property bool isPending: name !== "" && name === teleport.pendingCluster

    hasCursor: root.cursorActive && root.clusterIndex === rowIndex
    current: isCurrent
    foreground: root.foreground

    implicitHeight: rowContent.implicitHeight + Style.space(8)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      onEntered: root.setClusterCursor(clusterRow.rowIndex)
      onClicked: function (mouse) {
        if (mouse.button === Qt.MiddleButton) teleport.copyText(clusterRow.name)
        else teleport.selectCluster(clusterRow.name)
      }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Item {
        implicitWidth: rowIcon.implicitWidth
        implicitHeight: rowIcon.implicitHeight
        Layout.alignment: Qt.AlignVCenter

        Text {
          id: rowIcon
          visible: !clusterRow.isPending
          text: clusterRow.isCurrent ? "󰄬" : (clusterRow.isProduction ? "󰀦" : "󱃾")
          color: clusterRow.isProduction ? root.urgent : (clusterRow.isCurrent ? root.foreground : root.dim)
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }

        Spinner {
          anchors.centerIn: rowIcon
          running: clusterRow.isPending
          color: clusterRow.isProduction ? root.urgent : root.foreground
          fontSize: Style.font.icon
        }
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: clusterRow.name
          color: clusterRow.isProduction ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          visible: clusterRow.labels !== ""
          text: clusterRow.labels
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        visible: clusterRow.isProduction
        text: "prod"
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        visible: clusterRow.isCurrent
        text: "current"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
