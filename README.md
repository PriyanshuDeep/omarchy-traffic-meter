# Omarchy Traffic Meter

An Omarchy bar widget for live upload and download rates on the connected
physical network link. The panel shows the active Wi-Fi or Ethernet interface,
VPN state, and persistent data usage grouped by day, ISO week, month or year.

The usage collector counts physical interfaces, so switching between Wi-Fi and
Ethernet does not discard totals. It saves daily counters under
`$XDG_STATE_HOME/omarchy-traffic-meter/usage.json` (or
`~/.local/state/omarchy-traffic-meter/usage.json`) every five seconds and
retains daily history for up to 100 years. If the original Net Speed Colour
history file is present, the first run imports its saved usage into the new
state directory.

## Install

```bash
omarchy plugin add https://github.com/PriyanshuDeep/omarchy-traffic-meter.git --enable
```

To remove the widget and plugin:

```bash
omarchy plugin disable io.github.priyanshudeep.traffic-meter
omarchy plugin remove io.github.priyanshudeep.traffic-meter
```

Removing the plugin leaves its usage history in the state directory above.
Delete that directory separately if you also want to remove the history.

## Features

- Live upload and download rates for the active physical Wi-Fi or Ethernet
  interface, selected automatically from connected links.
- Usage totals across all physical interfaces, avoiding VPN double-counting.
- A history dropdown for daily dates, ISO weeks, calendar months and years.
- Persistent records across reboots and network interface counter resets.
- A short-lived VPN status and tunnel speed view.
- Selectable bar text weight: Normal, Medium, DemiBold or Bold.

The panel loads the complete saved history when opened. Measurements start
when the plugin is installed; traffic before that cannot be reconstructed.
Linux resets interface counters during reboot, so traffic in the final few
seconds before a sudden power loss or while the shell is stopped may not be
recorded.

## Settings

| Key | Default | Effect |
|---|---|---|
| `intervalMs` | `1000` | Poll interval from 500 to 5000 ms |
| `interface` | `auto` | Automatically select an active physical link, or pin an interface name |
| `units` | `bits` | Show bit/s or byte/s rates |
| `fontWeight` | `DemiBold` | Bar readout weight: Normal, Medium, DemiBold or Bold |

For example:

```bash
omarchy bar set io.github.priyanshudeep.traffic-meter fontWeight DemiBold
omarchy bar set io.github.priyanshudeep.traffic-meter units bytes
```

## Requirements and data handling

The collector uses Python 3's standard library and Linux `/sys` and `/proc`.
It runs no subprocesses, performs no network requests and executes no
downloaded code. Daily records are stored locally in a JSON file using atomic
replacement.

## Credits and license

This plugin is a modified derivative of
[Net Speed Colour by brightwalker25](https://github.com/brightwalker25/omarchy-net-speed),
used and modified under its MIT license. The original copyright and license
notices are retained in [LICENSE](LICENSE), and the README and manifest credit
the original author.

The feature concept was inspired by
[TrafficMonitor by zhongyang219](https://github.com/zhongyang219/TrafficMonitor);
no TrafficMonitor source code is included. Some bar and panel scaffolding is
derived from Omarchy's MIT-licensed shell plugins; its notice is also included
in [LICENSE](LICENSE).
