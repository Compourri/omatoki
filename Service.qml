import QtQuick
import Quickshell.Io

// Omatoki embeds the full weather panel, so the separate omarchy.weather pill is redundant.
// This one-shot disables it when Omatoki loads; user can re-enable manually if desired.
Item {
  id: root
  Process {
    id: disableWeather
    command: ["sh", "-c", "quickshell ipc -p /usr/share/omarchy/shell call shell setPluginEnabled \"omarchy.weather\" false 2>/dev/null || true"]
  }
  Timer {
    interval: 1000
    running: true
    repeat: false
    onTriggered: disableWeather.running = true
  }
}
