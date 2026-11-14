import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// The panel scaffolding here -- the open/close and IPC contract -- is derived
// from Omarchy's `omarchy.weather` and `omarchy.agents` plugins
// (https://github.com/basecamp/omarchy, MIT, Copyright (c) David Heinemeier
// Hansson). See LICENSE for the full notice.

// The panel behind the bar readout: the active physical link, VPN details,
// and persistent usage history grouped by day, ISO week, month or year.
//
// It runs nothing. The bar widget runs `bin/net-speed`, keeps the last two
// snapshots and derives the rates; this file reads all of that from
// `hostWidget` and draws it. Keeping one poller means the bar and the panel
// can never disagree about what the current speed is.
Panel {
  id: root
  moduleName: "io.github.priyanshudeep.traffic-meter"
  ipcTarget: "io.github.priyanshudeep.traffic-meter"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  // The bar tracks the widget mounted in its slot, not this nested panel, so
  // the popout coordinator has to be handed that widget as the identity.
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Traffic-light colours are fixed rather than drawn from the theme, and are
  // the same three the other brightwalker25 widgets use. A theme is free to
  // define its urgent colour as a soft pink, and a signal that reads as
  // decoration is not a signal.
  readonly property color okColor: "#3fb950"
  readonly property color warnColor: "#d29922"
  readonly property color badColor: "#f85149"

  // Up and down take the bar's colours, read from the bar widget so the two
  // cannot drift apart.
  readonly property color upColor: hostWidget ? hostWidget.upColor : "#58a6ff"
  readonly property color downColor: hostWidget ? hostWidget.downColor : "#3fb950"

  // ------------------------------------------------------ from the bar widget

  readonly property var snap: hostWidget && hostWidget.snapshot ? hostWidget.snapshot : null
  readonly property var link: snap && snap.link ? snap.link : null
  readonly property var history: hostWidget && hostWidget.history ? hostWidget.history : []

  function rateOf(name) {
    if (!hostWidget) return -1
    var v = hostWidget[name]
    return (v === undefined || v === null || !isFinite(v)) ? -1 : Number(v)
  }

  readonly property real linkRx: rateOf("linkRx")
  readonly property real linkTx: rateOf("linkTx")
  readonly property real tunnelRx: rateOf("tunnelRx")
  readonly property real tunnelTx: rateOf("tunnelTx")

  // The snapshot survives a failed run, so its tunnel entry alone could be
  // stale. The widget sets the tunnel rates to -1 whenever there is no tunnel
  // or the last run failed, and in both cases the panel must not claim one.
  readonly property var tunnel: snap && snap.tunnel && tunnelRx >= 0 ? snap.tunnel : null

  // ----------------------------------------------------------------- derived

  function kindLabel(kind) {
    if (kind === "wifi") return "Wi-Fi"
    if (kind === "ethernet") return "Ethernet"
    if (kind === "usb") return "USB"
    return "Link"
  }

  readonly property string linkLabel: link ? kindLabel(link.kind) : "Link"

  // What the tunnel costs on the wire. Every byte that goes through the
  // tunnel also crosses the physical link, wrapped in the tunnel's own
  // headers and encryption, so over the same minute the link carries more
  // than the tunnel does. The difference, as a share of the tunnel's own
  // bytes, is the overhead. Anything else on the link that bypasses the
  // tunnel (local network traffic, a split tunnel) counts too, so this is an
  // upper bound rather than a measurement of the protocol alone.
  //
  // Each history entry carries the seconds it covers, so rates are turned
  // back into bytes and the window is the last sixty seconds whatever the
  // refresh interval. Only entries where all four rates are known count, and
  // nothing is shown until the tunnel has averaged at least 1 KB/s over the
  // window: a percentage of almost nothing is noise.
  readonly property real overhead: {
    var h = root.history
    if (!h || h.length === 0 || !root.link || !root.tunnel) return -1
    var linkBytes = 0, tunBytes = 0, span = 0
    for (var i = h.length - 1; i >= 0 && span < 60; i--) {
      var e = h[i]
      var dt = e ? Number(e.dt) || 0 : 0
      if (dt <= 0 || e.rx < 0 || e.tx < 0 || e.trx < 0 || e.ttx < 0) continue
      linkBytes += (e.rx + e.tx) * dt
      tunBytes += (e.trx + e.ttx) * dt
      span += dt
    }
    if (span <= 0 || tunBytes / span < 1024) return -1
    // The two interfaces' counters are read a moment apart, so a quiet link
    // can briefly read under the tunnel. That is timing, not negative
    // overhead.
    return Math.max(0, (linkBytes - tunBytes) / tunBytes)
  }

  // The bar widget's own error covers a run that failed or could not be
  // parsed; the snapshot's covers a run that worked but found a problem.
  readonly property string errorText: {
    if (hostWidget && hostWidget.error) return String(hostWidget.error)
    return snap && snap.error ? String(snap.error) : ""
  }

  property string historyPeriod: "day"
  readonly property var usageHistory: hostWidget && hostWidget.usageHistory
    ? hostWidget.usageHistory : ({ days: [], weeks: [], months: [], years: [] })
  readonly property var historyEntries: {
    if (root.historyPeriod === "week") return root.usageHistory.weeks || []
    if (root.historyPeriod === "month") return root.usageHistory.months || []
    if (root.historyPeriod === "year") return root.usageHistory.years || []
    return root.usageHistory.days || []
  }

  function periodLabel(period, kind) {
    if (kind === "year") return String(period)
    if (kind === "month") {
      var p = String(period).split("-")
      return p.length === 2 ? Qt.formatDate(new Date(Number(p[0]), Number(p[1]) - 1, 1), "MMMM yyyy") : String(period)
    }
    if (kind === "week") {
      var w = String(period).split("-W")
      return w.length === 2 ? "Week " + w[1] + ", " + w[0] : String(period)
    }
    return root.fmtDay(period)
  }

  // -------------------------------------------------------------- formatting

  // Rates go through the bar widget so the panel honours the same units
  // setting as the bar. The fallback is only for the instant before the
  // widget is injected.
  function fmtRate(n) {
    if (hostWidget && typeof hostWidget.formatRate === "function") return hostWidget.formatRate(n)
    return (n === undefined || n < 0) ? "--" : fmtBytes(n) + "/s"
  }

  // Amounts of data are always bytes. Nobody reads a monthly allowance in bits.
  function fmtBytes(n) {
    if (n === undefined || n === null || n < 0 || !isFinite(n)) return "--"
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
    return (i > 0 && n < 10 ? n.toFixed(1) : Math.round(n)) + " " + units[i]
  }

  function fmtDay(iso) {
    var p = String(iso || "").split("-")
    if (p.length !== 3) return String(iso || "")
    var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
    return Qt.formatDate(d, "d MMM yyyy")
  }

  // ------------------------------------------------------- open/close contract

  property bool openedFromHotkey: false

  // The widget polls on its own timer whether or not the panel is open, so
  // opening asks for nothing more than a fresh sample if it offers one.
  function refresh() {
    if (hostWidget && typeof hostWidget.refresh === "function") hostWidget.refresh()
  }

  function open() {
    openedFromHotkey = false
    if (hostWidget && hostWidget.loadHistory) hostWidget.loadHistory()
    root.controller.show()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    if (hostWidget && hostWidget.loadHistory) hostWidget.loadHistory()
    root.controller.show()
  }

  function close() { root.controller.hide() }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      root.bar.switchPanelFrom(root.barIdentity, direction)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  // ------------------------------------------------------------- components

  component StatusDot: Rectangle {
    property color dotColor: root.dim
    implicitWidth: Style.space(9)
    implicitHeight: Style.space(9)
    radius: width / 2
    color: dotColor
    Behavior on color { ColorAnimation { duration: 180 } }
  }

  // Label on the left, value on the right, both on one baseline.
  component StatRow: Item {
    id: statRow
    property string label: ""
    property string value: ""
    property bool muted: false
    implicitHeight: Math.max(statLabel.implicitHeight, statValue.implicitHeight)

    Text {
      id: statLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: statRow.width - statValue.width - Style.spacing.controlGap
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: statRow.label
      color: statRow.muted ? root.dim : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: statValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: statRow.value
      color: statRow.muted ? root.dim : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  // One interface's speeds: a name on the left and two fixed-width columns on
  // the right, so the link and tunnel figures line up under each other and
  // can be compared at a glance.
  component SpeedRow: Item {
    id: speedRow
    property string label: ""
    property string up: ""
    property string down: ""
    property bool muted: false
    // Live rates take the up and down colours; a muted row stays dim.
    property bool tinted: false
    readonly property real column: Math.round(width * 0.3)
    implicitHeight: speedLabel.implicitHeight

    Text {
      id: speedLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: speedRow.width - 2 * speedRow.column
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: speedRow.label
      color: speedRow.muted ? root.dim : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.right: downText.left
      anchors.verticalCenter: parent.verticalCenter
      width: speedRow.column
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: speedRow.up
      color: speedRow.muted ? root.dim : speedRow.tinted ? root.upColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: downText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: speedRow.column
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: speedRow.down
      color: speedRow.muted ? root.dim : speedRow.tinted ? root.downColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  component SectionHeading: Column {
    id: heading
    property string title: ""
    spacing: Style.spacing.sm
    PanelSeparator { width: heading.width; foreground: root.foreground }
    PanelSectionHeader {
      text: heading.title
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }

  // ------------------------------------------------------------------ layout

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(820))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: historyDropdown.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: flick.width
          spacing: Style.spacing.lg

          // ---- Header: which interface is being measured, and whether a VPN
          // tunnel is up on top of it.
          Item {
            width: parent.width
            implicitHeight: Math.max(linkTitle.implicitHeight, vpnMarker.implicitHeight)

            Column {
              id: linkTitle
              anchors.left: parent.left
              anchors.right: vpnMarker.left
              anchors.rightMargin: Style.spacing.controlGap
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs

              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: root.link ? root.link.name : (root.snap ? "Offline" : "Waiting for first sample")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                width: parent.width
                visible: text !== ""
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: {
                  if (!root.link) return root.snap ? "no physical link is up" : ""
                  var how = root.link.reason === "pinned" ? "pinned in settings" : "chosen automatically"
                  return root.linkLabel + ", " + how
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              id: vpnMarker
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm
              visible: root.snap !== null

              StatusDot {
                anchors.verticalCenter: parent.verticalCenter
                dotColor: root.tunnel ? root.okColor : root.warnColor
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.tunnel ? "VPN up: " + root.tunnel.name : "VPN down"
                color: root.tunnel ? root.okColor : root.warnColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          // ---- Speeds: the physical link and the tunnel, one above the other
          // in the same two columns.
          Column {
            width: parent.width
            spacing: Style.spacing.md

            SectionHeading { width: parent.width; title: "SPEED" }

            SpeedRow {
              width: parent.width
              label: ""
              up: "↑ up"
              down: "↓ down"
              muted: true
            }

            SpeedRow {
              width: parent.width
              label: root.linkLabel
              up: root.link ? root.fmtRate(root.linkTx) : "--"
              down: root.link ? root.fmtRate(root.linkRx) : "--"
              muted: !root.link
              tinted: true
            }

            SpeedRow {
              width: parent.width
              label: root.tunnel ? "Tunnel  " + root.tunnel.name : "Tunnel"
              up: root.tunnel ? root.fmtRate(root.tunnelTx) : "--"
              down: root.tunnel ? root.fmtRate(root.tunnelRx) : "not up"
              muted: !root.tunnel
              tinted: true
            }

            StatRow {
              width: parent.width
              visible: root.overhead >= 0
              label: "Overhead"
              value: root.overhead >= 0 ? Math.round(root.overhead * 100) + "%" : ""
              muted: true
            }
          }

          // ---- Usage history: switch the view to daily, ISO-weekly, monthly or yearly totals.
          Column {
            width: parent.width
            spacing: Style.spacing.md
            visible: true

            Row {
              width: parent.width
              spacing: Style.spacing.md
              SectionHeading {
                width: parent.width - historyDropdown.width - parent.spacing
                title: "DATA USAGE"
              }
              Dropdown {
                id: historyDropdown
                width: 150
                showLabel: false
                fontFamily: root.fontFamily
                options: [
                  { value: "day", label: "Day" },
                  { value: "week", label: "Week" },
                  { value: "month", label: "Month" },
                  { value: "year", label: "Year" }
                ]
                value: root.historyPeriod
                onChanged: function(value) { root.historyPeriod = value }
              }
            }

            SpeedRow {
              width: parent.width
              label: ""
              up: "↑ upload"
              down: "↓ download"
              muted: true
            }

            Repeater {
              model: root.historyEntries
              delegate: SpeedRow {
                required property var modelData
                required property int index
                width: parent.width
                label: root.periodLabel(root.historyPeriod === "day" ? modelData.date : modelData.period, root.historyPeriod)
                up: root.fmtBytes(modelData.tx)
                down: root.fmtBytes(modelData.rx)
                muted: index > 0
              }
            }

            StatRow {
              width: parent.width
              visible: root.historyEntries.length === 0
              label: "No usage history recorded yet"
              value: ""
              muted: true
            }
          }

          // ---- Footer: anything that broke. A panel that silently draws
          // stale figures is the failure worth avoiding.
          Column {
            width: parent.width
            spacing: Style.spacing.xs
            visible: root.errorText !== ""

            PanelSeparator { width: parent.width; foreground: root.foreground }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.errorText
              color: root.badColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }
}
