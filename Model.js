// Omatoki Model.js — combined clock/calendar + weather helpers
// Keeps all pure logic Qt-free so `node Model.js` / qmllint can test it.
// Calendar/year/life math is lifted from omarchy.clock/Model.js (MIT).
// Weather helpers are lifted from omarchy.weather/Model.js (MIT).

var MS_PER_DAY = 86400000
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]
var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical) { return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice() }
function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var f = String(candidates[i] == null ? "" : candidates[i])
    if (f === "" || ring.indexOf(f) !== -1) continue
    ring.push(f)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}
function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var idx = ring.indexOf(String(current == null ? "" : current))
  return ring[(idx + 1) % ring.length]
}
function isoWeekLiteral(y, m, d) { return pad2(isoWeek(y, m, d)) }
function pad2(v) { var n = Number(v); return (n < 10 ? "0" : "") + n }
function dateKey(y, m, d) { return y + "-" + pad2(Number(m) + 1) + "-" + pad2(d) }
function keyForDate(d) { return dateKey(d.getFullYear(), d.getMonth(), d.getDate()) }

function coerceWeekStart(v) {
  if (v == null) return null
  if (typeof v === "number") return isFinite(v) ? ((Math.round(v) % 7) + 7) % 7 : null
  var t = String(v).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (t === "") return null
  for (var i = 0; i < WEEKDAY_NAMES.length; i++) if (WEEKDAY_NAMES[i] === t || WEEKDAY_NAMES[i].substr(0, 3) === t) return i
  var p = parseInt(t, 10)
  return isFinite(p) ? ((p % 7) + 7) % 7 : null
}
function normalizedWeekStart(v, fb) {
  var c = coerceWeekStart(v)
  if (c !== null) return c
  var f = coerceWeekStart(fb)
  return f === null ? 1 : f
}
function weekStartSettingName(i) { return WEEKDAY_NAMES[normalizedWeekStart(i, 1)] }
function toggledWeekStart(i) { return normalizedWeekStart(i, 1) === 1 ? 0 : 1 }
function weekdayOrder(ws) {
  var s = normalizedWeekStart(ws, 1), o = []
  for (var i = 0; i < 7; i++) o.push((s + i) % 7)
  return o
}
function isoWeek(y, m, d) {
  var dt = new Date(Date.UTC(y, m, d))
  var wd = dt.getUTCDay() || 7
  dt.setUTCDate(dt.getUTCDate() + 4 - wd)
  var ys = new Date(Date.UTC(dt.getUTCFullYear(), 0, 1))
  return Math.ceil(((dt.getTime() - ys.getTime()) / MS_PER_DAY + 1) / 7)
}
function dayOfYear(y, m, d) { return Math.round((Date.UTC(y, m, d) - Date.UTC(y, 0, 1)) / MS_PER_DAY) + 1 }
function daysInYear(y) { return dayOfYear(y, 11, 31) }
function yearProgress(y, m, d) {
  var tot = daysInYear(y)
  if (tot <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(y, m, d) - 1) / tot))
}
function yearProgressPercent(y, m, d) { return Math.round(yearProgress(y, m, d) * 100) }

var DEFAULT_LIFE_EXPECTANCY = 90
function parseBirthYear(v, cur) {
  var now = Math.round(Number(cur))
  if (!isFinite(now)) return 0
  var t = String(v == null ? "" : v).replace(/^\s+|\s+$/g, "")
  if (!/^\d{4}$/.test(t)) return 0
  var y = parseInt(t, 10)
  if (!isFinite(y) || y > now || y < now - 120) return 0
  return y
}
function ageFromBirthYear(by, cur) {
  var b = parseBirthYear(by, cur)
  if (b <= 0) return 0
  return Math.round(Number(cur)) - b
}
function parseAge(v) {
  var t = String(v == null ? "" : v).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(t)) return 0
  var n = parseInt(t, 10)
  if (!isFinite(n) || n <= 0 || n > 120) return 0
  return n
}
function parseLifeExpectancy(v) {
  var t = String(v == null ? "" : v).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(t)) return DEFAULT_LIFE_EXPECTANCY
  var n = parseInt(t, 10)
  if (!isFinite(n) || n <= 0 || n > 150) return DEFAULT_LIFE_EXPECTANCY
  return n
}
function lifeProgress(age, exp) {
  var y = parseAge(age), s = parseLifeExpectancy(exp)
  if (y <= 0 || s <= 0) return 0
  return Math.max(0, Math.min(1, y / s))
}
function lifeProgressPercent(age, exp) { return Math.round(lifeProgress(age, exp) * 100) }

// Fixed 6×7 grid — popup never jumps height when stepping months
function monthGrid(y, m, ws, todayKey) {
  var s = normalizedWeekStart(ws, 1)
  var lead = (new Date(y, m, 1).getDay() - s + 7) % 7
  var cur = new Date(y, m, 1 - lead)
  var today = String(todayKey || "")
  var weeks = []
  for (var w = 0; w < 6; w++) {
    var days = [], thu = null
    for (var d = 0; d < 7; d++) {
      var cy = cur.getFullYear(), cm = cur.getMonth(), cd = cur.getDate(), wd = cur.getDay()
      var k = dateKey(cy, cm, cd)
      if (wd === 4) thu = { year: cy, month: cm, day: cd }
      days.push({ key: k, year: cy, month: cm, day: cd, weekday: wd, inMonth: cm === m && cy === y, weekend: wd === 0 || wd === 6, today: k === today })
      cur.setDate(cur.getDate() + 1)
    }
    var a = thu || days[0]
    weeks.push({ week: isoWeek(a.year, a.month, a.day), days: days })
  }
  return weeks
}
function stepMonth(y, m, delta) {
  var t = new Date(y, Number(m) + Number(delta), 1)
  return { year: t.getFullYear(), month: t.getMonth() }
}
// Month progress (for the mock's "September — 68%" bar): days in the viewed month
function monthProgress(y, m, today) {
  var total = new Date(y, m + 1, 0).getDate()
  if (total <= 0) return 0
  // If viewing current month, progress = (today's date -1)/total, else 0 or 1
  var ty = today.getFullYear(), tm = today.getMonth(), td = today.getDate()
  if (y === ty && m === tm) return Math.max(0, Math.min(1, (td - 1) / total))
  var viewStart = new Date(y, m, 1), todayStart = new Date(ty, tm, 1)
  return viewStart < todayStart ? 1 : 0
}
function monthProgressPercent(y, m, today) { return Math.round(monthProgress(y, m, today) * 100) }

// ---- Weather helpers (from omarchy.weather/Model.js) ----
function parseLocationFile(raw) {
  var unset = { name: "", latitude: null, longitude: null }
  try {
    var d = JSON.parse(String(raw || ""))
    if (!d || typeof d !== "object") return unset
    var lat = parseFloat(d.latitude), lon = parseFloat(d.longitude)
    var has = !isNaN(lat) && !isNaN(lon)
    return { name: typeof d.name === "string" ? d.name.replace(/^\s+|\s+$/g, "") : "", latitude: has ? lat : null, longitude: has ? lon : null }
  } catch (e) { return unset }
}
function wttrLocationQuery(loc, lat, lon) {
  var la = parseFloat(String(lat)), lo = parseFloat(String(lon))
  if (!isNaN(la) && !isNaN(lo)) return la + "," + lo
  var n = String(loc || "").replace(/^\s+|\s+$/g, "")
  return n === "" ? "" : encodeURIComponent(n)
}
function parseGeocodingResults(raw) {
  try {
    var d = JSON.parse(String(raw || "{}")), r = d.results
    if (!r || !r.length) return []
    var out = []
    for (var i = 0; i < r.length; i++) {
      var x = r[i]
      if (!x || !x.name || x.latitude === undefined || x.longitude === undefined) continue
      var region = [x.admin1, x.country].filter(function(p) { return !!p }).join(", ")
      out.push({ name: String(x.name), description: region, latitude: x.latitude, longitude: x.longitude })
    }
    return out
  } catch (e) { return [] }
}
function locationCommit(text, sugg, idx) {
  var n = String(text || "").replace(/^\s+|\s+$/g, "")
  if (n === "") return { name: "", latitude: null, longitude: null }
  var c = sugg || [], i = Math.max(0, Math.min(parseInt(idx, 10) || 0, c.length - 1))
  var s = c[i]
  if (s) return s
  return { name: n, latitude: null, longitude: null }
}
function isFutureForecastDate(ds, todayStr) { if (!ds) return false; return String(ds).slice(0, 10) > String(todayStr || "") }
function roundedTemp(v) { if (v == null || v === "") return ""; var n = parseFloat(String(v)); return isNaN(n) ? "" : String(Math.round(n)) }
function celsiusToFahrenheit(v) { if (v == null || v === "") return ""; var n = parseFloat(String(v)); return isNaN(n) ? "" : (n * 9 / 5) + 32 }
function formatTemp(v, imp) { if (v == null || v === "") return ""; return v + "°" + (imp ? "F" : "C") }
function normalizedUnit(v) { return String(v || "").replace(/^\s+|\s+$/g, "").toLowerCase() }
function localeUsesImperial(n) { var s = String(n || "").replace(".", "_"); return /^en[_-]US($|[_.-])/.test(s) || /^en[_-]LR($|[_.-])/.test(s) || /^my($|[_.-])/.test(s) }
function countryUsesImperial(c) {
  var s = String(c || "").replace(/^\s+|\s+$/g, "").replace(/[._-]+/g, " ").toLowerCase()
  if (!s) return null
  if (s === "us" || s === "usa" || s === "united states" || s === "united states of america") return true
  if (s === "liberia" || s === "myanmar" || s === "burma") return true
  return false
}
function shouldUseImperial(unit, loc, country) {
  var u = normalizedUnit(unit)
  if (u === "imperial") return true
  if (u === "metric") return false
  var cp = countryUsesImperial(country)
  if (cp !== null) return cp
  return localeUsesImperial(loc)
}
function dayName(ds, fmt) {
  if (!ds) return ""
  var d = new Date(ds + "T12:00:00")
  if (isNaN(d.getTime())) return ""
  if (fmt) return fmt(d)
  return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d.getDay()]
}
function openMeteoForecastDays(rep, todayStr) {
  var daily = rep && rep.daily ? rep.daily : null
  if (!daily || !daily.time) return []
  var out = []
  for (var i = 0; i < daily.time.length && out.length < 3; ++i) {
    var dt = daily.time[i]
    if (!isFutureForecastDate(dt, todayStr)) continue
    var maxC = daily.temperature_2m_max ? daily.temperature_2m_max[i] : ""
    var minC = daily.temperature_2m_min ? daily.temperature_2m_min[i] : ""
    out.push({ date: dt, maxtempC: roundedTemp(maxC), mintempC: roundedTemp(minC), maxtempF: roundedTemp(celsiusToFahrenheit(maxC)), mintempF: roundedTemp(celsiusToFahrenheit(minC)), openMeteoWeatherCode: daily.weather_code ? daily.weather_code[i] : null })
  }
  return out
}
function openMeteoCurrentCondition(rep) {
  var c = rep && rep.current ? rep.current : null
  if (!c || c.temperature_2m == null) return null
  return { temp_C: roundedTemp(c.temperature_2m), temp_F: roundedTemp(celsiusToFahrenheit(c.temperature_2m)), FeelsLikeC: roundedTemp(c.apparent_temperature), FeelsLikeF: roundedTemp(celsiusToFahrenheit(c.apparent_temperature)), windspeedKmph: roundedTemp(c.wind_speed_10m), windspeedMiles: roundedTemp(c.wind_speed_10m * 0.621371), humidity: roundedTemp(c.relative_humidity_2m), openMeteoWeatherCode: c.weather_code, isDay: c.is_day }
}
function currentIcon(cur, fb) {
  if (!cur) return fb || ""
  if (cur.openMeteoWeatherCode != null) return iconForOpenMeteoCode(cur.openMeteoWeatherCode, Number(cur.isDay) === 0)
  if (cur.weatherCode != null) return iconForCode(cur.weatherCode, false)
  return fb || ""
}
function provisionalCurrentIcon(cur, ri) { return ri || currentIcon(cur, "") }
function wttrNextForecastDays(rep, todayStr) {
  var days = rep && rep.weather ? rep.weather : [], out = []
  for (var i = 0; i < days.length && out.length < 3; ++i) if (isFutureForecastDate(days[i].date, todayStr)) out.push(days[i])
  return out
}
function buildForecastDays(rep, daily, todayStr) {
  var d = openMeteoForecastDays(daily, todayStr)
  return d.length > 0 ? d : wttrNextForecastDays(rep, todayStr)
}
function bareTempForDay(day, kind, imp) {
  if (!day) return ""
  var v = imp ? (kind === "max" ? day.maxtempF : day.mintempF) : (kind === "max" ? day.maxtempC : day.mintempC)
  if (v == null || v === "") return ""
  return v + "°"
}
function dayIcon(day) {
  if (!day) return ""
  if (day.openMeteoWeatherCode != null) return iconForOpenMeteoCode(day.openMeteoWeatherCode)
  if (!day.hourly || day.hourly.length === 0) return ""
  var best = day.hourly[0], bd = 9999
  for (var i = 0; i < day.hourly.length; ++i) { var t = parseInt(String(day.hourly[i].time || "0"), 10), d = Math.abs(t - 1200); if (d < bd) { bd = d; best = day.hourly[i] } }
  return iconForCode(best.weatherCode, false)
}
function iconForOpenMeteoCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  if (c === 0) return iconForCode(113, night)
  if (c === 1 || c === 2) return iconForCode(116, night)
  if (c === 3) return iconForCode(119, night)
  if (c === 45 || c === 48) return iconForCode(143, night)
  if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61) return iconForCode(266, night)
  if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82) return iconForCode(308, night)
  if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86) return iconForCode(338, night)
  if (c === 95 || c === 96 || c === 99) return iconForCode(389, night)
  return iconForCode(119, night)
}
function iconForCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  switch (c) {
    case 113: return night ? "" : ""
    case 116: return night ? "" : ""
    case 119: case 122: return ""
    case 143: case 248: case 260: return night ? "\ue346" : "\ue313"
    case 176: case 263: case 353: return night ? "" : ""
    case 179: case 227: case 230: case 323: case 326: case 368: return night ? "" : ""
    case 182: case 185: case 281: case 284: case 311: case 314: case 317: case 320: case 350: case 362: case 365: case 374: case 377: return ""
    case 200: case 386: case 389: case 392: case 395: return ""
    case 266: case 293: case 296: case 299: case 302: case 305: case 308: case 356: case 359: return ""
    case 329: case 332: case 335: case 338: case 371: return ""
    default: return ""
  }
}
function weatherResponseCompletesSave(hasCoords, src) { return hasCoords ? src === "open-meteo" : src === "wttr" }

if (typeof module !== "undefined") {
  module.exports = {
    dateKey, keyForDate, normalizedWeekStart, weekStartSettingName, toggledWeekStart, weekdayOrder,
    isoWeek, dayOfYear, daysInYear, yearProgress, yearProgressPercent,
    parseBirthYear, ageFromBirthYear, parseAge, parseLifeExpectancy, lifeProgress, lifeProgressPercent,
    monthGrid, stepMonth, monthProgress, monthProgressPercent,
    clockFormats, clockFormatRing, nextClockFormat, isoWeekLiteral, pad2,
    parseLocationFile, wttrLocationQuery, parseGeocodingResults, locationCommit,
    isFutureForecastDate, roundedTemp, celsiusToFahrenheit, formatTemp, shouldUseImperial,
    dayName, openMeteoForecastDays, openMeteoCurrentCondition, currentIcon, provisionalCurrentIcon,
    buildForecastDays, bareTempForDay, dayIcon, iconForOpenMeteoCode, iconForCode, wttrNextForecastDays, weatherResponseCompletesSave
  }
}
