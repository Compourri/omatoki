# Omatoki — おまとき

Clock, calendar, and weather in one Omarchy panel.

Omatoki shows the time, date, month grid, and forecast together. You get a large clock, year and life progress, a full month view, and current conditions with a 3-day forecast. It replaces the default clock and keeps everything that clock does.

![Omatoki preview](preview.png)

## Install

```sh
omarchy plugin add https://github.com/compourri/omatoki.git --enable --yes
omarchy bar move io.github.compourri.omatoki --section center
```

Manual install:

```sh
mkdir -p ~/.config/omarchy/plugins/io.github.compourri.omatoki
cp -r BarWidget.qml Panel.qml Model.js manifest.json ~/.config/omarchy/plugins/io.github.compourri.omatoki/
quickshell ipc -p /usr/share/omarchy/shell call shell rescanPlugins
omarchy plugin enable io.github.compourri.omatoki
```

## Use

* Click the clock to open or close the panel. You can also run `omarchy-shell shell summon io.github.compourri.omatoki '{}'`.
* Right-click the clock to cycle the bar format. Omatoki writes your choice to `shell.json`.
* Middle-click the clock to open the timezone picker.
* Press `W` or click the `W` header to switch the week start between Monday and Sunday.
* Press `[` and `]` or scroll to change month. Press `{` and `}` to change year. Press `T` to return to today.
* Double-click the year bar to set your birth year and life expectancy. The life bar appears after you set a year. Double-click it to clear.
* Click the location name to search for a city. Press Enter to save, Up and Down to pick a suggestion, and `×` to clear and return to automatic detection.

## Configure

Edit the entry in `~/.config/omarchy/shell.json`:

```json
{
  "id": "io.github.compourri.omatoki",
  "format": "dddd HH:mm",
  "weekStartDay": "monday",
  "birthYear": 1995,
  "lifeExpectancy": 90,
  "unit": "metric",
  "refreshMinutes": 15
}
```

Omatoki stores the weather location in `~/.local/state/omarchy/settings/weather.json` and shares it with `omarchy.weather`. If you clear the location, it detects your city from your IP address and falls back to `wttr.in` and `open-meteo` for data.

## Remove

```sh
omarchy plugin remove io.github.compourri.omatoki
```

The built-in clock returns automatically.

## Credits

* Calendar and life progress logic from `omarchy.clock`
* Weather and geocoding logic from `omarchy.weather`
* Panel layout based on the default clock and weather panels

## License

MIT — see [LICENSE](LICENSE).
