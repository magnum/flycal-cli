# flycal-cli

[![Gem Version](https://badge.fury.io/rb/flycal-cli.svg)](https://badge.fury.io/rb/flycal-cli) 

A command-line tool to access and search Google Calendar events. Connect your Google account, choose a default calendar, and search events with flexible date ranges and text filters.

## Requirements

- Ruby 3.1 or later
- A Google Cloud project with Calendar API enabled

## Installation

```bash
gem install flycal-cli
```

Or add to your Gemfile:

```ruby
gem "flycal-cli"
```

Then run `bundle install`.

## Setup

Before using flycal, you need OAuth credentials from Google Cloud Console:

1. Go to [Google Cloud Console - Credentials](https://console.cloud.google.com/apis/credentials)
2. Create a project or select an existing one
3. Enable the **Google Calendar API** (APIs & Services → Library → search for "Google Calendar API")
4. Create **Desktop app** credentials (OAuth 2.0 Client IDs)
5. Add this URI as an authorized redirect:
   ```
   http://127.0.0.1:9292/oauth2callback
   ```
6. Download the JSON file and save it as `~/.flycal/credentials.json`

## Commands

All commands support a per-invocation locale override:

```bash
flycal search --locale it --in 7days
flycal slots --locale en --in "3 days" --duration 1h
```

### login

Connect to your Google account. Opens a browser for OAuth authentication when not yet connected.

```bash
flycal login
```

If already connected, the command reports the current status and suggests running `flycal config` to set the default calendar.

### logout

Disconnect from your Google account and remove stored tokens.

```bash
flycal logout
```

### update

Update `flycal-cli` to the latest published gem version.

```bash
flycal update
```

### version

Show the current installed `flycal-cli` version.

```bash
flycal version
flycal --version
flycal -v
```

### calendars

List available calendars with name and ID.

```bash
flycal calendars
```

Example output:

```
Work user@example.com
Personal user@gmail.com
```

### config

Interactive configuration menu.

```bash
flycal config
```

Options:

- `calendar_default` — choose the default calendar and save it to `~/.flycal/config.yml`
- `exclude_calendars` — multi-select one or more calendars whose events block free slots (default selection includes the current default calendar)
- `edit config` — open `~/.flycal/config.yml` with `$EDITOR` (or `vi`)

Press Ctrl+C during configuration to cancel without error (`config cancelled...`).

The default calendar is used by the search command when no calendar is specified.

### search

Search for events in your calendar(s). Supports flexible date ranges and text filtering.

```bash
flycal search
flycal search --in 30days --description placeholder
flycal search -f 2025-03-01 -t 2025-03-31 -c "Work"
flycal search -i 2months -d placeholder
```

**Options:**

- `--from` / `-f` — Start date/time. Default: midnight of current day. Formats: `YYYY-MM-DD`, locale forms (`DD-MM-YYYY` for `it`, `MM-DD-YYYY` for `en`, `/` or `-`), or with time `YYYY-MM-DDTHH:MM`
- `--to` / `-t` — End date/time. Default: 23:59 of the 30th day from today. Same formats as `--from`
- `--in` / `-i` — Duration from `--from`, overrides `--to`. Format: `30days`, `48hours`, `2months`, `1year` (no space). With space use quotes: `--in "30 days"`
- `--calendar` / `-c` — Calendar name or ID. Default: calendar set via `flycal config`
- `--description` / `-d` — Filter events by text. Matches events where the string appears in title or description (case-insensitive, contains)

**Time range behavior:**

- If neither `--from` nor `--to` is given: searches from today at midnight to 23:59 of the 30th day from today
- If `--in` is given: `--to` is ignored; the end time is computed from `--from` plus the duration
- Examples: `--in 30days`, `--in 48hours`, `--in 1months`, `--in 1year`

**Output:**

Each event is printed as: `Calendar | Start | End | Title`

The summary shows:
- From and To dates used
- Number of events found
- Total time occupied (hours, minutes, and working days based on 8-hour days)

For time frames longer than 7 days, a weekly breakdown is added (week number, start/end dates, hours, working days per week). For time frames longer than 30 days, a monthly breakdown is shown instead (month number, month name, hours, working days per month).

### slots

Find free time slots in your calendar. Output is a simple list for copy/paste into email or other tools.

```bash
flycal slots
flycal slots --in "5 days"
flycal slots --in "12 days" --template dinner
flycal slots --duration 1h
flycal slots --from 2026-08-01 --in "2 weeks" --duration 1h
```

**Options:**

- `--duration` — Slot length. Default: `slots.defaults.default_duration` in config (`45min`). Examples: `1h`, `30 minutes`
- `--from` / `-f` — Start date/time. Default: `slots.defaults.from` in config (`now`). If a date without time is today, starts from the current time.
- `--in` / `-i` — Search window from `--from`. Default: `1 week`.
- `--template` / `-T` — Template from `slots.templates` in config. Default: first template (`work`)
- `--calendar` / `-c` — Calendar name or ID used as fallback when `exclude_calendars` is not configured

**Output:**

```
found 6 slots
from sat 1 August 2026 to sat 8 August 2026
with duration 45min, template dinner
considering calendars
- incode - antonio
- Polimi 10110009
- antoniomolinari1977@gmail.com
link: https://calendar.google.com/calendar/r/day/2026/8/1

saturday 1/8
19 - 23

monday 3/8
19 - 23
```

If `pbcopy` is available (macOS), the slot list without the header is also copied to the clipboard.

Slot search windows are configured in `~/.flycal/config.yml`:

```yaml
calendar_default: ~
locale: en
slots:
  templates:
    work:
      days:
        - 1
        - 2
        - 3
        - 4
        - 5
      hours:
        - 9:30-13:00
        - 14:00-18:30
    dinner:
      days:
        - 1
        - 2
        - 3
        - 4
        - 5
        - 6
        - 7
      hours:
        - 19-23
  exclude_calendars: []
  defaults:
    from: now
    default_duration: 45min
  free_before: 0m
  free_after: 15m
```

Missing keys are filled from `config/defaults.yml` in the gem and saved to your `config.yml` on first read.

- `calendar_default: ~` means no default calendar is set (`~` is YAML null)
- `templates` — named schedules; default used is the first one (`work`)
- `templates.*.days` — weekdays as numbers: `1` Monday … `7` Sunday
- `templates.*.hours` — one or more ranges (`H-H`, `HH:MM-HH:MM`, mixed)
- `defaults.from` — default `--from` for slots (`now` or a date string)
- `defaults.default_duration` — default slot length when `--duration` is omitted
- `free_before` — buffer before each slot
- `free_after` — buffer after each slot; gaps must fit `duration + free_after`, output shows continuous free ranges
- `exclude_calendars` — calendars whose events block free slots; if empty, `calendar_default` is used
- `locale` supports `en` and `it` (default is `en`)

**Output example:**

```
friday 15/7
10 - 12
13 - 15.30

monday 21/7
12 - 13
14 - 15
```

## Configuration

Data is stored in `~/.flycal/`:

| File | Purpose |
|:-----|---------|
| `config.yml` | Default calendar ID and other settings |
| `credentials.json` | OAuth credentials (created manually from Google Cloud Console) |
| `tokens.yml` | Access tokens (managed automatically) |

## Publishing to RubyGems

### First release

1. Create an account at [rubygems.org](https://rubygems.org) if needed
2. Update `flycal-cli.gemspec` with your author, email, and homepage
3. Build and push:

```bash
gem build flycal-cli.gemspec
gem push flycal-cli-0.1.0.gem
```

### Subsequent releases

1. Update the version in `lib/flycal_cli/version.rb`
2. Build and push:

```bash
gem build flycal-cli.gemspec
gem push flycal-cli-X.Y.Z.gem
```

3. Optionally tag and push:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

### Using rake release

With `bundler/gem_tasks` in your Rakefile:

```bash
bundle exec rake release
```

This builds the gem, pushes to RubyGems, and can handle git tagging and pushing.

## License

MIT
