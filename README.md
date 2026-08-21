# flycal-cli

[![Gem Version](https://badge.fury.io/rb/flycal-cli.svg)](https://badge.fury.io/rb/flycal-cli)

Read your Google Calendar from the terminal: search events, find free slots, copy them into an email. **Read-only** — nothing is modified on the calendar.

## Quick start

```bash
gem install flycal-cli
flycal login
```

During the test phase the project already provides the Google API credentials.  
Open the browser, approve access, done.

Optional but useful once:

```bash
flycal config          # set default calendar + calendars that block free slots
flycal calendars       # list calendars (name + id)
```

## Common examples

**Find free slots (most useful day-to-day)**

```bash
flycal slots
flycal slots --in "5 days"
flycal slots --from monday --in "5 days"
flycal slots --from "next monday" --in "2 weeks" --duration 1h
flycal slots --in "12 days" --template dinner
flycal slots --locale it --from lunedi --in "5 days"
```

Output is a short header plus a clean list ready to paste (and copied to the clipboard when `pbcopy` / `clip` / `wl-copy` / `xclip` is available):

```
found 6 slots
from sat 1 August 2026 to sat 8 August 2026
with duration 45min, template dinner
considering calendars
- Work
- Personal
link: https://calendar.google.com/calendar/r/day/2026/8/1

saturday 1/8
19 - 23

monday 3/8
19 - 23
```

**Search events**

```bash
flycal search
flycal search --in 30days
flycal search --in 30days --description meeting
flycal search --from 2026-08-01 --to 2026-08-31 -c Work
flycal search --from monday --in "2 weeks" --locale it
```

**Other commands**

```bash
flycal version
flycal update
flycal logout
```

All commands accept `--locale en|it`.

---

## Configuration (`~/.flycal/config.yml`)

Defaults are created automatically on first run. Edit with `flycal config` → `edit config`, or by hand.

```yaml
calendar_default: ~
locale: en
slots:
  templates:
    work:
      days: [1, 2, 3, 4, 5]          # 1=Mon … 7=Sun
      hours:
        - 9:30-13:00
        - 14:00-18:30
    dinner:
      days: [1, 2, 3, 4, 5, 6, 7]
      hours:
        - 19-23
  exclude_calendars: []              # calendars whose events block free slots
  defaults:
    from: now
    default_duration: 45min
  free_before: 0m
  free_after: 15m
```

| Key | Meaning |
|---|---|
| `calendar_default` | Default calendar (`~` = unset) |
| `locale` | `en` or `it` |
| `slots.templates` | Named schedules; `flycal slots` uses the first one unless `--template` is set |
| `slots.exclude_calendars` | Events here block free slots (fallback: `calendar_default`) |
| `slots.defaults.*` | Defaults for `--from` / `--duration` |
| `slots.free_before` / `free_after` | Buffers around busy events |

Interactive helpers:

```bash
flycal config
```

- `calendar_default` — pick the default calendar  
- `exclude_calendars` — multi-select calendars that block slots  
- `edit config` — open the YAML in `$EDITOR`

---

## Parameters (reference)

### `flycal slots`

| Option | Default | Notes |
|---|---|---|
| `--duration` | `45min` | Min free range length (`1h`, `90min`, …) |
| `--from` / `-f` | `now` | Absolute date or relative: `monday`, `next monday`, `tomorrow`, `lunedi`, … |
| `--in` / `-i` | `1 week` | Window from `--from` (`"5 days"`, `2weeks`, …) |
| `--template` / `-T` | first template (`work`) | e.g. `dinner` |
| `--calendar` / `-c` | — | Fallback if `exclude_calendars` is empty |
| `--locale` | config / `en` | `en` or `it` |

### `flycal search`

| Option | Default | Notes |
|---|---|---|
| `--from` / `-f` | today midnight | Absolute or relative date |
| `--to` / `-t` | +30 days | Ignored if `--in` is set |
| `--in` / `-i` | — | Duration from `--from` |
| `--description` / `-d` | — | Contains filter on title/description |
| `--calendar` / `-c` | `calendar_default` | Name or ID |
| `--locale` | config / `en` | `en` or `it` |
| `--format` | `text` | Output format (`text`; `json` coming soon) |

Relative dates work in English and Italian: `today`/`oggi`, `tomorrow`/`domani`, `monday`/`lunedi`, `next monday`/`prossimo lunedi`, `last friday`/`scorso venerdi`.

---

## Optional: your own Google Cloud credentials

**Not needed** for the default test API — `flycal login` is enough.

Use this only if you want flycal to talk to **your own** Google Cloud OAuth client instead of the project-provided test credentials.

1. [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials)
2. Enable **Google Calendar API**
3. Create **Desktop app** OAuth credentials
4. Authorized redirect URI: `http://127.0.0.1:9292/oauth2callback`
5. Save the JSON as `~/.flycal/credentials.json`
6. Run `flycal login`

You can also ask a teammate who manages the Cloud project to share that JSON with you.

---

## Files

| Path | Purpose |
|---|---|
| `~/.flycal/config.yml` | Settings (calendars, templates, locale, …) |
| `~/.flycal/credentials.json` | Own OAuth client (optional) |
| `~/.flycal/tokens.yml` | Login tokens (managed automatically) |

MCP catalog for agents: [`mcp/tools.json`](mcp/tools.json)

## License

MIT
