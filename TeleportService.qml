import QtQuick
import Quickshell
import Quickshell.Io

// Teleport session state, kube cluster list, and the actions the panel drives.
// Everything shells out to the two helper scripts in bin/.
QtObject {
  id: root

  property var settings: ({})
  property string pluginDir: ""

  // "off" | "expired" | "active"
  property string sessionState: "off"
  property string cluster: ""
  property string user: ""
  property string proxy: ""
  property string roles: ""
  property string validUntil: ""
  property real validEpoch: 0
  property string statusText: ""

  property var clusters: []
  property bool clustersLoading: false
  property bool busy: false
  property string actionStatus: ""
  property string lastError: ""

  readonly property bool active: sessionState === "active"
  // Deny by default: a cluster is production unless its name says otherwise.
  readonly property string nonProductionPattern: settings && settings.nonProductionPattern
    ? settings.nonProductionPattern
    : "(^|[-_])(dev|devel|develop|development|stag|staging|test|testing|demo|sandbox|acc|acceptance|qa|preview|local)([-_]|$)"
  readonly property bool useTerminal: settings && settings.useTerminal === true
  readonly property string loginCommand: settings && settings.loginCommand
    ? settings.loginCommand
    : "source ~/.config/bash/tsh-login.sh && tsh-login"

  // Seconds left on the cert, recomputed by the panel's ticking clock.
  property real nowEpoch: 0
  readonly property real secondsLeft: validEpoch > 0 && nowEpoch > 0 ? validEpoch - nowEpoch : 0

  // True only when a valid session is genuinely close to running out.
  readonly property bool expiringSoon: active && validEpoch > 0 && nowEpoch > 0 && secondsLeft > 0 && secondsLeft < 1800

  readonly property string remainingText: {
    if (!active) return "expired"
    var s = secondsLeft
    if (s <= 0) return "expired"
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    if (h >= 24) return Math.floor(h / 24) + "d " + (h % 24) + "h left"
    if (h > 0) return h + "h " + m + "m left"
    return Math.max(1, m) + "m left"
  }

  signal refreshed()

  function script(name) {
    return pluginDir + "/bin/" + name
  }

  function run(command) {
    actionProc.command = ["bash", "-lc", command]
    actionProc.running = true
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function refreshClusters() {
    if (!active) { clusters = []; return }
    if (clustersProc.running) return
    clustersLoading = true
    clustersProc.running = true
  }

  function login(cluster) {
    if (busy) return
    actionStatus = "Logging in…"
    lastError = ""
    busy = true
    if (useTerminal) {
      loginProc.command = ["omarchy-launch-floating-terminal-with-presentation", "bash", "-lc", loginCommand]
    } else {
      loginProc.command = cluster ? [script("teleport-login"), cluster] : [script("teleport-login")]
    }
    loginProc.running = true
    relogin.restart()
  }

  function logout() {
    actionStatus = "Logging out…"
    busy = true
    run("tsh logout")
    Qt.callLater(refresh)
  }

  // Goes through tsh-kube-login so an expired cert re-authenticates via
  // 1Password instead of failing the switch.
  function selectCluster(name) {
    if (!name || busy) return
    actionStatus = "Switching to " + name + "…"
    lastError = ""
    busy = true
    kubeLoginProc.command = [script("teleport-login"), name]
    kubeLoginProc.running = true
  }

  function notify(title, body) {
    notifyProc.command = ["notify-send", "-a", "Teleport", title, body]
    notifyProc.running = true
  }

  function copyText(value) {
    if (!value) return
    copyProc.command = ["bash", "-lc", "printf %s " + shellQuote(value) + " | wl-copy"]
    copyProc.running = true
    actionStatus = "Copied"
    statusFade.restart()
  }

  // A bad user-supplied pattern falls back to warning about everything.
  readonly property var _nonProductionRegex: {
    try {
      return new RegExp(nonProductionPattern, "i")
    } catch (e) {
      return null
    }
  }

  function isProduction(name) {
    if (!name) return false
    return !_nonProductionRegex || !_nonProductionRegex.test(String(name))
  }

  readonly property bool onProduction: active && isProduction(cluster)

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  property Process _statusProc: Process {
    id: statusProc
    command: [root.script("teleport-status")]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          root.sessionState = data.state || "off"
          root.cluster = data.cluster || ""
          root.user = data.user || ""
          root.proxy = data.proxy || ""
          root.roles = data.roles || ""
          root.validUntil = data.validUntil || ""
          root.validEpoch = data.validEpoch || 0
          root.statusText = data.status || ""
          root.lastError = ""
        } catch (e) {
          root.sessionState = "off"
          root.cluster = ""
          root.lastError = "teleport-status failed"
        }
        root.nowEpoch = Math.floor(Date.now() / 1000)
        root.refreshed()
      }
    }
  }

  property Process _clustersProc: Process {
    id: clustersProc
    command: [root.script("teleport-clusters")]
    stdout: StdioCollector {
      onStreamFinished: {
        root.clustersLoading = false
        try {
          var list = JSON.parse(text)
          root.clusters = Array.isArray(list) ? list : []
        } catch (e) {
          root.clusters = []
        }
      }
    }
  }

  property Process _kubeLoginProc: Process {
    id: kubeLoginProc
    stdout: StdioCollector {}
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") root.lastError = text.trim()
    }
    onExited: function (exitCode) {
      root.busy = false
      root.actionStatus = exitCode === 0 ? "" : "Cluster switch failed"
      if (exitCode !== 0) root.notify("Cluster switch failed", root.lastError)
      root.refresh()
      root.refreshClusters()
    }
  }

  property Process _loginProc: Process {
    id: loginProc
    stdout: StdioCollector {}
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") root.lastError = text.trim()
    }
    onExited: function (exitCode) {
      root.busy = false
      if (root.useTerminal) return
      if (exitCode === 0) {
        root.actionStatus = ""
      } else {
        relogin.stop()
        root.actionStatus = "Login failed"
        root.notify("Teleport login failed", root.lastError)
      }
      root.refresh()
      root.refreshClusters()
    }
  }

  property Process _notifyProc: Process {
    id: notifyProc
  }

  property Process _actionProc: Process {
    id: actionProc
    onExited: {
      root.busy = false
      root.refresh()
    }
  }

  property Process _copyProc: Process {
    id: copyProc
  }

  // After a login was started, poll for a while so the panel picks the new
  // session up without waiting for the regular interval.
  property Timer _relogin: Timer {
    id: relogin
    interval: 5000
    repeat: true
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks++
      root.refresh()
      if (ticks >= 24 || root.active) {
        stop()
        root.actionStatus = ""
        if (root.active) root.refreshClusters()
      }
    }
  }

  property Timer _statusFade: Timer {
    id: statusFade
    interval: 1500
    onTriggered: root.actionStatus = ""
  }
}
