import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omatoki — one panel to rule them all: hero clock + year/life + calendar + weather.
// Keeps every omarchy.clock interaction (week start, birthYear, month stepping)
// and every omarchy.weather interaction (location search, units, refresh, forecast).
Panel {
  id: root
  moduleName: "io.github.compourri.omatoki"
  ipcTarget: "io.github.compourri.omatoki"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ----- Clock / Calendar state -----
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property real monthDone: Model.monthProgress(viewYear, viewMonth, today)
  readonly property int monthDonePercent: Model.monthProgressPercent(viewYear, viewMonth, today)
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  // ----- Weather state -----
  property var report: null
  property var dailyForecastReport: null
  property string wttrLocation: ""
  property var configuredLocationState: ({ name: "", latitude: null, longitude: null })
  readonly property string configuredLocation: configuredLocationState.name
  readonly property string locationQuery: Model.wttrLocationQuery(configuredLocationState.name, configuredLocationState.latitude, configuredLocationState.longitude)
  property bool openedFromHotkey: false
  onLocationQueryChanged: {
    if (savingLocation) savingLocationQueryStarted = true
    forecastRetries = 0; dailyForecastRetries = 0
    forecastProc.running = false; dailyForecastProc.running = false
    Qt.callLater(refreshWeather)
  }
  property FileView locationFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.configuredLocationState = Model.parseLocationFile(text())
    onLoadFailed: root.configuredLocationState = Model.parseLocationFile("")
  }
  Timer { interval: 1500; running: true; onTriggered: locationFile.reload() }
  property int forecastRetries: 0
  property int dailyForecastRetries: 0
  property bool editingLocation: false
  property bool savingLocation: false
  property bool savingLocationQueryStarted: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""
  property string label: ""
  readonly property bool hasConfiguredCoordinates: !isNaN(parseFloat(String(configuredLocationState.latitude))) && !isNaN(parseFloat(String(configuredLocationState.longitude)))
  readonly property var openMeteoCurrent: Model.openMeteoCurrentCondition(dailyForecastReport)
  readonly property var current: (hasConfiguredCoordinates && openMeteoCurrent) ? openMeteoCurrent : ((report && report.current_condition && report.current_condition[0]) ? report.current_condition[0] : openMeteoCurrent)
  readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
  readonly property var forecastDays: buildForecastDays()
  readonly property string reportCountry: areaInfo && areaInfo.country && areaInfo.country[0] ? areaInfo.country[0].value : ""
  readonly property bool useImperial: Model.shouldUseImperial(setting("unit", ""), Qt.locale().name, reportCountry)
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)
  readonly property string reportLocation: configuredLocation || wttrLocation || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : "")
  readonly property string reportTempNum: current ? String(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string tempUnit: "°" + (useImperial ? "F" : "C")
  readonly property string reportFeels: current ? formatTemp(useImperial ? current.FeelsLikeF : current.FeelsLikeC) : ""
  readonly property string reportWind: current ? (useImperial ? (current.windspeedMiles + " mph") : (current.windspeedKmph + " km/h")) : ""
  readonly property string reportHumidity: current ? (current.humidity + "%") : ""

  // ----- Shared open/close -----
  function open() {
    refresh()
    root.controller.show()
    locationFile.reload()
    refreshWeather()
    Qt.callLater(function() { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }
  function openFromHotkey() { openedFromHotkey = true; open() }
  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingLife) cancelEditingLife()
    if (root.editingLocation) cancelEditingLocation()
    root.controller.hide()
  }
  function toggle() { if (root.opened) root.close(); else root.open() }
  function switchPanel(d) { if (root.bar && typeof root.bar.switchPanelFrom === "function") return root.bar.switchPanelFrom(root.barIdentity, d); return false }
  function setCenterHoverRevealSuppressed(v) { if (root.bar && "centerHoverRevealSuppressed" in root.bar) root.bar.centerHoverRevealSuppressed = v }
  function refresh() {
    root.today = new Date()
    // keep viewingCurrentMonth sticky across midnight
    var follow = root.viewingCurrentMonth
    if (follow) goToToday()
  }
  function goToToday() { root.viewYear = today.getFullYear(); root.viewMonth = today.getMonth() }
  function moveMonth(delta) { var n = Model.stepMonth(viewYear, viewMonth, delta); root.viewYear = n.year; root.viewMonth = n.month }
  function moveYear(delta) { moveMonth(delta * 12) }
  function persistSettings(vals) {
    var e = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") e[k] = root.settings[k]
    for (var kk in vals) e[kk] = vals[kk]
    root.settings = e
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = e
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") root.bar.shell.updateEntryInline(root.moduleName, e)
  }
  function setWeekStart(d) { var n = Model.normalizedWeekStart(d, root.weekStart); if (n === root.weekStart) return; persistSettings({ weekStartDay: Model.weekStartSettingName(n) }) }
  function toggleWeekStart() { setWeekStart(Model.toggledWeekStart(root.weekStart)) }
  function weekdayLabel(wd) { return String(labelLocale.dayName(wd, Locale.ShortFormat)).toUpperCase() }
  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() { bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""; expectancyField.text = String(root.lifeExpectancy); bornField.selectAll(); bornField.forceActiveFocus() })
  }
  function cancelEditingLife() { root.editingLife = false; Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() }) }
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) { cancelEditingLife(); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { commitLife(); event.accepted = true }
    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { other.selectAll(); other.forceActiveFocus(); event.accepted = true }
  }
  function clearLife() { if (root.birthYear <= 0) return; persistSettings({ birthYear: 0 }) }
  function commitLife() {
    var b = Model.parseBirthYear(bornField.text, today.getFullYear())
    var s = Model.parseLifeExpectancy(expectancyField.text)
    if (b !== root.birthYear || s !== root.lifeExpectancy) persistSettings({ birthYear: b, lifeExpectancy: s })
    cancelEditingLife()
  }

  // ----- Weather helpers -----
  function refreshWeather() {
    forecastRetries = 0; dailyForecastRetries = 0
    if (!forecastProc.running) forecastProc.running = true
    if (root.locationQuery === "" && !locationProc.running) locationProc.running = true
    refreshDailyForecast(null)
  }
  function refreshDailyForecast(src) {
    if (dailyForecastProc.running) return
    var lat = parseFloat(String(root.configuredLocationState.latitude)), lon = parseFloat(String(root.configuredLocationState.longitude))
    if (isNaN(lat) || isNaN(lon)) {
      var area = src && src.nearest_area && src.nearest_area[0] ? src.nearest_area[0] : root.areaInfo
      if (!area) return
      lat = parseFloat(String(area.latitude || "")); lon = parseFloat(String(area.longitude || ""))
    }
    if (isNaN(lat) || isNaN(lon)) return
    var url = "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(String(lat)) + "&longitude=" + encodeURIComponent(String(lon)) + "&daily=weather_code,temperature_2m_max,temperature_2m_min&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day&forecast_days=4&timezone=auto"
    dailyForecastProc.command = ["curl", "-fsS", "--max-time", "5", url]
    dailyForecastProc.running = true
  }
  function startEditingLocation() {
    editingLocation = true; savingLocation = false; savingLocationQueryStarted = false
    locationSuggestions = []; suggestionIndex = 0
    Qt.callLater(function() { locationField.text = root.configuredLocation; locationField.selectAll(); locationField.forceActiveFocus() })
  }
  function cancelEditingLocation() { editingLocation = false; savingLocation = false; savingLocationQueryStarted = false; locationSuggestions = []; geocodeDebounce.stop(); Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() }) }
  function commitLocation() {
    var loc = Model.locationCommit(locationField.text, locationSuggestions, suggestionIndex)
    if (loc.name === "") { clearLocation(); return }
    savingLocation = true; savingLocationQueryStarted = false
    configuredLocationState = { name: loc.name, latitude: loc.latitude, longitude: loc.longitude }
    persistLocation(loc.name, loc.latitude, loc.longitude)
  }
  function clearLocation() { persistLocation("", null, null); wttrLocation = ""; cancelEditingLocation() }
  function pickSuggestion(s) { if (!s) return; savingLocation = true; savingLocationQueryStarted = false; configuredLocationState = { name: s.name, latitude: s.latitude, longitude: s.longitude }; persistLocation(s.name, s.latitude, s.longitude) }
  function finishSavingLocation() { if (savingLocation && savingLocationQueryStarted) cancelEditingLocation() }
  function persistLocation(n, lat, lon) {
    if (n && lat !== null && lon !== null) locationSaveProc.command = ["omarchy-weather-location", "--set", n, lat + "," + lon]
    else if (n) locationSaveProc.command = ["omarchy-weather-location", "--set", n]
    else locationSaveProc.command = ["omarchy-weather-location", "--clear"]
    locationSaveProc.running = true
  }
  function requestGeocode() { var q = locationField.text.trim(); if (q.length < 2) { locationSuggestions = []; return } geocodePendingQuery = q; if (!geocodeProc.running) startGeocode() }
  function startGeocode() { geocodeActiveQuery = geocodePendingQuery; geocodeProc.command = ["curl", "-fsS", "--max-time", "5", "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"]; geocodeProc.running = true }
  function buildForecastDays() { return Model.buildForecastDays(report, dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd")) }
  function bareTempForDay(d, k) { return Model.bareTempForDay(d, k, useImperial) }
  function dayIcon(d) { return Model.dayIcon(d) }
  function dayName(ds) { return Model.dayName(ds, function(date) { return Qt.formatDate(date, "dddd") }) }
  function formatTemp(v) { return Model.formatTemp(v, useImperial) }
  function scheduleForecastRetry() { if (forecastRetries >= 3) return; forecastRetries++; forecastRetryTimer.restart() }
  function scheduleDailyForecastRetry() { if (dailyForecastRetries >= 3) return; dailyForecastRetries++; dailyForecastRetryTimer.restart() }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var follow = root.viewingCurrentMonth
      root.today = clock.date
      if (follow) root.goToToday()
    }
  }

  // ----- Processes -----
  Process {
    id: forecastProc
    command: ["curl", "-fsS", "--max-time", "10", "https://wttr.in/" + root.locationQuery + "?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) { root.scheduleForecastRetry(); return }
        try {
          var p = JSON.parse(raw)
          root.report = p
          if (!root.hasConfiguredCoordinates) root.label = Model.provisionalCurrentIcon(p.current_condition && p.current_condition[0], root.label)
          root.forecastRetries = 0
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "wttr")) root.finishSavingLocation()
          if (isNaN(parseFloat(String(root.configuredLocationState.latitude)))) root.refreshDailyForecast(p)
        } catch (e) { root.scheduleForecastRetry() }
      }
    }
  }
  Timer { id: forecastRetryTimer; interval: 2500; onTriggered: if (!forecastProc.running) forecastProc.running = true }
  Timer { id: dailyForecastRetryTimer; interval: 2500; onTriggered: root.refreshDailyForecast(null) }
  Process {
    id: dailyForecastProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) { root.scheduleDailyForecastRetry(); return }
        try {
          var p = JSON.parse(raw)
          var cur = Model.openMeteoCurrentCondition(p)
          root.dailyForecastReport = p
          root.label = Model.currentIcon(cur, root.label)
          root.dailyForecastRetries = 0
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "open-meteo")) root.finishSavingLocation()
        } catch (e) { root.scheduleDailyForecastRetry() }
      }
    }
  }
  Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.locationSuggestions = root.editingLocation ? Model.parseGeocodingResults(text) : []
        root.suggestionIndex = 0
        if (root.geocodePendingQuery !== root.geocodeActiveQuery) Qt.callLater(root.startGeocode)
      }
    }
  }
  Timer { id: geocodeDebounce; interval: 300; onTriggered: root.requestGeocode() }
  Process {
    id: locationSaveProc
    onExited: function(code) {
      if (code !== 0 || !root.savingLocation) return
      locationFile.reload()
      if (!root.savingLocationQueryStarted) {
        root.savingLocationQueryStarted = true
        root.forecastRetries = 0; root.dailyForecastRetries = 0
        forecastProc.running = false; dailyForecastProc.running = false
        Qt.callLater(root.refreshWeather)
      }
    }
  }
  Process {
    id: locationProc
    command: ["curl", "-fsS", "--max-time", "4", "https://wttr.in/?format=%l"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var r = String(text || "").trim(); if (!r) return; root.wttrLocation = r.split(",")[0] } }
  }
  Timer { id: refreshTimer; interval: root.refreshMinutes * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refreshWeather() }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function edit(): void { root.openFromHotkey(); root.startEditingLocation() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(580))
    contentHeight: panel.fittedContentHeight(omatokiColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife || root.editingLocation
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.moveMonth(dx); if (dy !== 0) root.moveYear(dy) }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1); else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1); else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Flickable {
        id: omatokiScroll
        anchors.fill: parent
        contentWidth: omatokiColumn.width
        contentHeight: omatokiColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: omatokiColumn
          width: Math.max(omatokiScroll.width, gridColumn.width + Style.space(32))
          spacing: Style.space(10)

          // ---- HERO CLOCK: 15:10 / Monday / September 7 ----
          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Qt.formatTime(clock.date, "HH:mm")
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: 56
              font.bold: true
              font.letterSpacing: -1
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Qt.formatDate(root.today, "dddd")
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: 34
              font.weight: Font.Light
            }
            Item {
              width: parent.width
              height: heroDateRow.height
              Row {
                id: heroDateRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(10)
                Text {
                  anchors.baseline: heroDateText.baseline
                  text: "󰃭"
                  color: heroMouse.containsMouse ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: 28
                }
                Text {
                  id: heroDateText
                  text: Qt.formatDate(root.today, "MMMM d")
                  color: heroMouse.containsMouse ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: 24
                  font.bold: true
                  font.letterSpacing: 1
                }
              }
              MouseArea {
                id: heroMouse
                x: heroDateRow.x; y: heroDateRow.y; width: heroDateRow.width; height: heroDateRow.height
                enabled: !root.viewingCurrentMonth
                hoverEnabled: enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goToToday()
                PanelToolTip { visible: heroMouse.containsMouse; text: "Back to today"; fontFamily: root.contentFontFamily }
              }
            }
          }

          // ---- Year progress (mock's "2026 — 68%" rail) ----
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height
            Item {
              id: yearBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))
              TapHandler { enabled: !root.editingLife; onDoubleTapped: root.startEditingLife() }
              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "BORN"; color: Qt.darker(root.contentForeground, 1.5); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 }
                TextField { id: bornField; width: Style.space(70); anchors.verticalCenter: parent.verticalCenter; placeholderText: "year"; foreground: root.contentForeground; font.family: root.contentFontFamily; inputMethodHints: Qt.ImhDigitsOnly; Keys.onPressed: function(e) { root.handleLifeKey(e, expectancyField) } }
                Text { leftPadding: Style.space(6); anchors.verticalCenter: parent.verticalCenter; text: "LIVE TO"; color: Qt.darker(root.contentForeground, 1.5); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 }
                TextField { id: expectancyField; width: Style.space(60); anchors.verticalCenter: parent.verticalCenter; placeholderText: "90"; foreground: root.contentForeground; font.family: root.contentFontFamily; inputMethodHints: Qt.ImhDigitsOnly; Keys.onPressed: function(e) { root.handleLifeKey(e, bornField) } }
              }
              Text { id: yearLabel; visible: !root.editingLife; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: root.today.getFullYear(); color: Qt.darker(root.contentForeground, 1.5); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 }
              Text { visible: !root.editingLife; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.yearDonePercent + "%"; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall }
              Rectangle {
                visible: !root.editingLife
                anchors.left: yearLabel.right; anchors.right: parent.right
                anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(40)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6); radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                Rectangle { width: Math.round(parent.width * root.yearDone); height: parent.height; radius: parent.radius; color: Style.selectedStateColor(root.contentForeground, Color.accent); Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
              }
            }
          }

          // ---- Life progress (memento mori) ----
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0
            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))
              Text { id: lifeLabel; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "LIFE"; color: Qt.darker(root.contentForeground, 1.5); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 }
              Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.lifeDonePercent + "%"; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall }
              Rectangle {
                anchors.left: lifeLabel.right; anchors.right: parent.right
                anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(40)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6); radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                Rectangle { width: Math.round(parent.width * root.lifeDone); height: parent.height; radius: parent.radius; color: Style.selectedStateColor(root.contentForeground, Color.accent); Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
              }
              TapHandler { onDoubleTapped: root.clearLife() }
              MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton; PanelToolTip { visible: parent.containsMouse; text: "Memento Mori — double-click to clear"; fontFamily: root.contentFontFamily } }
            }
          }

          // ---- Calendar grid ----
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height
            WheelHandler { onWheel: function(e) { if (e.angleDelta.y === 0) return; root.moveMonth(e.angleDelta.y > 0 ? -1 : 1) } }
            Column {
              id: gridColumn
              y: Style.space(10)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)
              Row {
                id: headerRow
                spacing: root.cellSpacing
                Rectangle {
                  width: root.weekColumnWidth; height: Style.space(16); radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                  Text { anchors.centerIn: parent; text: "W"; color: weekStartMouse.containsMouse ? Style.hoverStateColor(root.contentForeground, Color.accent) : Qt.darker(root.contentForeground, 1.9); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1; font.bold: true }
                  MouseArea { id: weekStartMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleWeekStart() }
                  PanelToolTip { visible: weekStartMouse.containsMouse; text: "Start weeks on " + root.nextWeekStartLabel; fontFamily: root.contentFontFamily }
                }
                Item { width: root.gutterWidth; height: Style.space(16) }
                Repeater {
                  model: root.weekdays
                  Text { required property var modelData; width: root.cellWidth; height: Style.space(16); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: root.weekdayLabel(modelData); color: Qt.darker(root.contentForeground, 1.5); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1; font.bold: true }
                }
              }
              Repeater {
                model: root.weeks
                Row {
                  required property var modelData
                  spacing: root.cellSpacing
                  Text { width: root.weekColumnWidth; height: root.cellHeight; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: modelData.week; color: Qt.darker(root.contentForeground, 1.9); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
                  Item { width: root.gutterWidth; height: root.cellHeight }
                  Repeater {
                    model: modelData.days
                    Rectangle {
                      required property var modelData
                      width: root.cellWidth; height: root.cellHeight; radius: Style.cornerRadius
                      color: "transparent"
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)
                      Text { anchors.centerIn: parent; text: modelData.day; color: modelData.inMonth ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground) : Qt.darker(root.contentForeground, 2.2); font.family: root.contentFontFamily; font.pixelSize: Style.font.body; font.bold: modelData.today }
                    }
                  }
                }
              }
            }
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline; height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground; opacity: 0.1
            }
          }

          // ---- Month nav ----
          Item {
            width: parent.width; height: monthNav.height
            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabelText.implicitHeight + Style.space(10)
              Text {
                id: monthLabelText
                anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter
                width: Style.space(150); horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4); font.family: root.contentFontFamily; font.pixelSize: Style.font.body; font.letterSpacing: 1
              }
              PanelActionButton { anchors.left: parent.left; anchors.leftMargin: -Style.space(8); anchors.verticalCenter: parent.verticalCenter; iconText: "󰅁"; tooltipText: "Previous month"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: root.moveMonth(-1) }
              PanelActionButton { anchors.right: parent.right; anchors.rightMargin: -Style.space(8); anchors.verticalCenter: parent.verticalCenter; iconText: "󰅂"; tooltipText: "Next month"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: root.moveMonth(1) }
            }
          }

          // ---- Divider ----
          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.contentForeground; opacity: 0.12 }

          // ---- Weather hero ----
          Item {
            width: parent.width
            height: Math.max(weatherLeft.height, weatherRight.height)
            Row {
              id: weatherLeft
              anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(12)
              Text {
                anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 2
                text: root.label || "—"
                color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: 48
              }
              Row {
                anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(2)
                Text { text: root.reportTempNum || "—"; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: 42; font.bold: true }
                Text { text: root.current ? root.tempUnit : ""; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.display; anchors.top: parent.top; anchors.topMargin: Style.space(6) }
              }
            }
            Column {
              id: weatherRight
              width: weatherStats.implicitWidth
              anchors.right: parent.right; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)
              Row {
                visible: !root.editingLocation && root.reportLocation !== ""
                spacing: Style.space(6)
                TapHandler { onTapped: root.startEditingLocation() }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                Text { text: ""; color: Qt.darker(root.contentForeground, 1.4); font.family: root.contentFontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
                Text { text: (root.reportLocation || "").toUpperCase(); color: Qt.darker(root.contentForeground, 1.4); font.family: root.contentFontFamily; font.pixelSize: Style.font.body; font.letterSpacing: 1; anchors.verticalCenter: parent.verticalCenter }
              }
              Row {
                visible: root.editingLocation; spacing: Style.space(6)
                TextField {
                  id: locationField
                  width: Style.space(170); enabled: !root.savingLocation
                  placeholderText: "Search city"; foreground: root.contentForeground; font.family: root.contentFontFamily
                  onTextChanged: if (root.editingLocation && !root.savingLocation) geocodeDebounce.restart()
                  Keys.onPressed: function(e) {
                    if (e.key === Qt.Key_Escape) { root.cancelEditingLocation(); e.accepted = true }
                    else if (e.key === Qt.Key_Down) { if (root.suggestionIndex < root.locationSuggestions.length - 1) root.suggestionIndex++; e.accepted = true }
                    else if (e.key === Qt.Key_Up) { if (root.suggestionIndex > 0) root.suggestionIndex--; e.accepted = true }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.commitLocation(); e.accepted = true }
                  }
                }
                Rectangle {
                  width: Style.space(18); height: Style.space(18); anchors.verticalCenter: parent.verticalCenter
                  radius: Math.min(4, Style.cornerRadius); color: !root.savingLocation && clearLocArea.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                  Text { anchors.centerIn: parent; text: root.savingLocation ? "󰦖" : "✕"; color: Qt.darker(root.contentForeground, 1.4); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; RotationAnimator on rotation { running: root.savingLocation; from: 0; to: 360; duration: 800; loops: Animation.Infinite } }
                  MouseArea { id: clearLocArea; anchors.fill: parent; enabled: !root.savingLocation; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clearLocation() }
                }
              }
              Row {
                id: weatherStats; visible: !!root.current; spacing: Style.space(28)
                Column { spacing: Style.space(4); Text { text: "FEELS"; color: Qt.darker(root.contentForeground, 1.5); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 } Text { text: root.reportFeels; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.title } }
                Column { spacing: Style.space(4); Text { text: "WIND"; color: Qt.darker(root.contentForeground, 1.5); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 } Text { text: root.reportWind; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.title } }
                Column { spacing: Style.space(4); Text { text: "HUMID"; color: Qt.darker(root.contentForeground, 1.5); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 } Text { text: root.reportHumidity; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.title } }
              }
            }
          }

          // ---- Geocoding suggestions ----
          Column {
            visible: root.editingLocation && !root.savingLocation && root.locationSuggestions.length > 0
            width: parent.width; spacing: 0
            Repeater {
              model: root.locationSuggestions
              Rectangle {
                required property var modelData; required property int index
                width: parent.width; height: suggRow.implicitHeight + Style.space(12); radius: Style.cornerRadius
                color: index === root.suggestionIndex ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                Row {
                  id: suggRow; anchors.left: parent.left; anchors.leftMargin: Style.space(16); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(8)
                  Text { text: modelData.name; color: index === root.suggestionIndex ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.body }
                  Text { visible: text !== ""; text: modelData.description; color: Qt.darker(root.contentForeground, 1.5); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onPositionChanged: root.suggestionIndex = index; onClicked: root.pickSuggestion(modelData) }
              }
            }
          }

          Text { visible: !root.current; text: "Fetching forecast…"; color: Qt.darker(root.contentForeground, 1.5); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; font.italic: true }

          Rectangle { visible: root.forecastDays.length > 0; width: parent.width; height: Style.spacing.hairline; color: root.contentForeground; opacity: 0.12 }

          // ---- 3-day forecast ----
          Item {
            visible: root.forecastDays.length > 0
            width: parent.width; height: forecastRow.height
            Row {
              id: forecastRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(36)
              Repeater {
                model: root.forecastDays
                Row {
                  required property var modelData
                  spacing: Style.space(8)
                  Text { anchors.verticalCenter: parent.verticalCenter; text: root.dayIcon(modelData); color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.display }
                  Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(2)
                    Text { text: root.dayName(modelData.date).toUpperCase(); color: Qt.darker(root.contentForeground, 1.4); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1 }
                    Row {
                      spacing: Style.space(6)
                      Text { text: root.bareTempForDay(modelData, "max"); color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.body }
                      Text { text: root.bareTempForDay(modelData, "min"); color: Qt.darker(root.contentForeground, 1.5); font.family: root.contentFontFamily; font.pixelSize: Style.font.body }
                    }
                  }
                }
              }
            }
          }

          // ---- Footer hint ----
          Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: "Double-click year bar to set life • Right-click bar clock to cycle format"
            color: Qt.darker(root.contentForeground, 2.0); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption; font.italic: true
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
