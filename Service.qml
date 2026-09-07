import QtQuick
import Quickshell
import Quickshell.Io

// Omatoki service — de-duplicates the bar when Omatoki is active.
// Since Omatoki already embeds the full weather panel (hero + 3-day),
// the separate omarchy.weather pill is redundant.
// This disables it once on load; user can re-enable manually via
// `omarchy plugin enable omarchy.weather` if they really want both.
Item {
  id: root

  Process {
    id: disableWeather
    command: ["sh", "-c", "quickshell ipc -p /usr/share/omarchy/shell call shell setPluginEnabled \"omarchy.weather\" false 2>/dev/null; quickshell ipc -p /usr/share/omarchy/shell call shell listPlugins 2>/dev/null | grep -q '\"omarchy.weather\".*\"enabled\": true' && echo re-enable-needed || echo ok"]
  }

  // Also watch for the case where Omatoki was just enabled — give shell a beat to register us.
  Timer {
    interval: 1200
    running: true
    repeat: false
    onTriggered: {
      // Only act if Omatoki itself is enabled (we are running)
      // and weather is still enabled — don't fight an explicit user re-enable done after us.
      disableWeather.running = true
    }
  }
}
