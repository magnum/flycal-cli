# Changelog

## [Unreleased]

## [0.7.8] - 2026-08-21

### Changed

- `--groupBy` string mode: any value other than `day`/`week`/`month` is split on `|` for grouping (independent from `--description`)

## [0.7.7] - 2026-08-21

### Added

- `--description` OR terms with `|` (case-insensitive)
- `--groupBy day|week|month|description` to override auto grouping
- JSON group fields: `from`/`to` as `YYYYMMDDTHHMMSS` (time groups); `description` for description groups

## [0.7.6] - 2026-08-21

### Added

- `--format json` via `JsonRenderer`: pretty JSON with `params`, `info`, `items`, `groups`

## [0.7.5] - 2026-08-21

### Added

- Mock calendars for `flycal search` (templates, seed, no Google API in mock mode)
- Search pipeline layers: `Retriever` → `Aggregator` → `Renderer` (`TextRenderer`); shared `Params` object across the pipeline
- Global `--format` option (default `text`)
- `mcp/tools.json` machine-readable catalog of CLI commands for MCP servers (schemas, argv templates, auth/interactivity flags)
- RSpec suite for mock calendars, search filtering, and TextRenderer output (`bundle exec rspec`)
- `flycal config` interactive menu to set `calendar_default`, `exclude_calendars`, or open `~/.flycal/config.yml` with `$EDITOR`
- `slots.exclude_calendars` in config: events from these calendars block free slots; if empty, falls back to `calendar_default`
- Automatic migration of legacy config keys (`exclude-calendars` → `exclude_calendars`, `weekdays-only` → `weekdays_only`, `workhours` → `hours`)
- Centralized `DateTimeParser` for locale-aware date parsing (`YYYY-MM-DD`, `DD-MM-YYYY` for `it`, `MM-DD-YYYY` for `en`, `/` or `-`)
- `flycal slots --from` to start the search window from a given date/time (default: now)
- `slots.defaults`, `free_before`, and `free_after` in config for slot search defaults and buffers

### Changed

- `flycal calendars` now only lists calendars (name and ID); default calendar is set via `flycal config`
- Config keys renamed for consistency: `weekdays_only`, `exclude_calendars`
- In `flycal config`, the current default calendar and already-selected exclude calendars are shown bold and underlined
- Slot schedules use `slots.templates` (`work`, `dinner`, …) with explicit `days` (1=Mon…7=Sun) and `hours`; `--template` selects which one (default: first)
- Removed `weekdays_only` / top-level `hours` in favor of templates
- `flycal slots --in` defaults to `1 week`; `--duration` is optional (defaults from config)
- `flycal slots` uses `free_before` / `free_after` buffers and reports continuous free ranges (aggregated), each at least as long as `--duration`
- `flycal slots` prints a header with duration/window and clickable Google Calendar links before availability

### Fixed

- `exclude_calendars` multi-select no longer crashes when preselecting configured calendar IDs (tty-prompt expects choice labels as defaults)

## [0.4.1] - 2026-07-29

### Added

- `./release.sh` script to automate version bump, gem build, and optional RubyGems push

## [0.4.0] - 2026-07-29

### Added

- `flycal slots` command to find available time slots in your calendar
- `flycal update` command to update the installed gem via `gem update flycal-cli`
- `flycal version` command to show the current version (`flycal --version` / `-v` also supported)
- i18n support with `locale` in `~/.flycal/config.yml` and per-command override via `--locale` (English and Italian)
- `config/defaults.yml` as the source of default settings; missing keys are merged into the user config on read

### Changed

- Slot search settings moved from CLI flags to `~/.flycal/config.yml` under `slots:`
- Work hours now support multiple ranges per day (e.g. `9:30-13:00` and `14:00-18:30` for lunch breaks)
- `weekdays_only` is configurable in `config.yml` instead of via a CLI option
- Gemspec now packages `config/` and `locales/` files required at runtime

## [0.3.2] - 2026-07-29

Previous stable release before the 0.4.x feature set.

## [0.1.0] - 2025-02-26

### Added

- `flycal login` for Google OAuth authentication
- `flycal logout` to disconnect
- `flycal calendars` to list calendars and set the default (interactive TTY::Prompt menu)
- `flycal search` to search events with filters (`--from`, `--to`, `--calendar`, `--description`)
- Configuration stored in `~/.flycal/config.yml`
- Support for `google-apis-calendar_v3`
