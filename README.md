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

- `--from` / `-f` — Start date/time. Default: midnight of current day. Format: `2025-01-01` or `2025-01-01T09:00`
- `--to` / `-t` — End date/time. Default: 23:59 of the 30th day from today. Format: same as `--from`
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

Find free time slots in your calendar (weekdays, 9:00–18:00). Output is a simple list for copy/paste into email or other tools.

```bash
flycal slots --in "3 days" --duration 1h
flycal slots --in 1week --duration 30min
flycal slots --in "48 hours" --duration 1hour -c Work
```

**Options:**

- `--duration` — Minimum slot length. Examples: `1h`, `1 hour`, `30 minutes`, `90min`
- `--in` / `-i` — Search window from now. Examples: `3 days`, `1 week`, `48 hours` (use quotes when the value contains a space)
- `--calendar` / `-c` — Calendar name or ID used as fallback when `exclude_calendars` is not configured

Slot search windows are configured in `~/.flycal/config.yml`:

```yaml
slots:
  exclude_calendars:
    - user@example.com
    - user@gmail.com
  workhours:
    - 9:30-13:00
    - 14:00-18:30
  weekdays_only: true
locale: en
```

Missing keys are filled from `config/defaults.yml` in the gem and saved to your `config.yml` on first read.

- `exclude_calendars` lists calendars whose events block free slots; if empty or not set, events from `calendar_default` are used
- `workhours` accepts one or more ranges (`H-H`, `HH:MM-HH:MM`, mixed)
- `weekdays_only: true` limits slots to Monday-Friday
- `weekdays_only: false` includes weekends
- `locale` supports `en` and `it` (default is `en`)

**Output example:**

```
friday 15/7
10-12
13-15.30

monday 21/7
12-13
14-15
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
