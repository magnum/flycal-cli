# flycal MCP catalog

Machine-readable description of **flycal-cli** for MCP servers.

## File

- [`tools.json`](./tools.json) — full catalog:
  - `global_options` / `shared_formats` — shared `--locale`, date and duration formats
  - `config.keys` — `~/.flycal/config.yml` keys used by the CLI
  - `tools[].parameters` — human-readable parameter docs (cli flags, defaults, examples)
  - `tools[].inputSchema` — JSON Schema for MCP tool registration
  - `command.option_map` — how to build argv from tool arguments

## How an MCP server can use it

1. Load `tools.json` at startup.
2. Register each entry in `tools` with your MCP SDK using `name`, `description`, and `inputSchema`.
3. On tool call, build argv:
   - static tools → `command.argv`
   - parameterized tools → start from `command.argv_template`, then for each provided arg append `command.option_map[arg]`
   - if `locale` is set → append `--locale <value>`
4. Run `flycal` as a subprocess and return stdout as text.
5. Skip tools with `"interactive": true` (`flycal_login`, `flycal_config`) unless a TTY is available.

## Parameters cheat sheet

### Global

| Param | CLI | Values |
|---|---|---|
| `locale` | `--locale` | `en`, `it` |

### `flycal_search`

| Param | CLI | Default | Notes |
|---|---|---|---|
| `calendar` | `--calendar` / `-c` | `calendar_default` | name or ID |
| `from` | `--from` / `-f` | today midnight | absolute or relative date |
| `to` | `--to` / `-t` | +30 days 23:59 | ignored if `in` set |
| `in` | `--in` / `-i` | — | duration from `from`, overrides `to` |
| `description` | `--description` / `-d` | — | contains filter |
| `locale` | `--locale` | config/`en` | |

### `flycal_slots`

| Param | CLI | Default | Notes |
|---|---|---|---|
| `duration` | `--duration` | `45min` (config) | min free-range length |
| `from` | `--from` / `-f` | `now` (config) | absolute or relative (`monday`, `next monday`, …) |
| `in` | `--in` / `-i` | `1 week` | window from `--from` |
| `template` | `--template` / `-T` | first template (`work`) | from `slots.templates` |
| `calendar` | `--calendar` / `-c` | — | fallback if `exclude_calendars` empty |
| `locale` | `--locale` | config/`en` | |

### Relative `--from` examples

`now`, `today`/`oggi`, `tomorrow`/`domani`, `monday`/`lunedi`, `next monday`/`prossimo lunedi`, `last friday`/`scorso venerdi`

## Suggested tools to expose

| MCP tool | CLI | Notes |
|---|---|---|
| `flycal_search` | `flycal search ...` | Primary read tool |
| `flycal_slots` | `flycal slots ...` | Free slots |
| `flycal_calendars` | `flycal calendars` | List name + id |
| `flycal_version` | `flycal version` | Health / version check |

Interactive / side-effect tools (`login`, `logout`, `config`, `update`) are documented but usually better left to a user terminal.
