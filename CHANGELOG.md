# Changelog

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
- `weekdays-only` is configurable in `config.yml` instead of via a CLI option
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
