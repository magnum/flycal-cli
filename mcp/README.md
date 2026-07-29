# flycal MCP catalog

This directory contains a machine-readable description of **flycal-cli** commands for MCP (Model Context Protocol) servers.

## File

- [`tools.json`](./tools.json) — tools catalog with MCP-style `inputSchema`, CLI argv templates, auth/interactivity flags, and config keys.

## How an MCP server can use it

1. Load `tools.json` at startup.
2. Register each entry in `tools` with your MCP SDK (`server.tool(...)`), using `name`, `description`, and `inputSchema`.
3. On tool call, build the argv:
   - static tools → `command.argv`
   - parameterized tools → start from `command.argv_template`, then append pairs from `command.option_map` for each provided argument
   - if `locale` is set → append `--locale <value>`
4. Run `flycal` as a subprocess and return stdout as text content.
5. Skip or gate tools with `"interactive": true` (`flycal_login`, `flycal_config`) unless a TTY is available.

## Suggested tools to expose

| MCP tool | CLI | Notes |
|---|---|---|
| `flycal_search` | `flycal search ...` | Primary read tool |
| `flycal_slots` | `flycal slots --in ... --duration ...` | Free slots |
| `flycal_calendars` | `flycal calendars` | List name + id |
| `flycal_version` | `flycal version` | Health / version check |

Interactive / side-effect tools (`login`, `logout`, `config`, `update`) are documented in the catalog but are usually better left to the user terminal.
