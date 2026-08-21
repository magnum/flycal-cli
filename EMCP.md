# flycal-cli → EmCP integration brief

Guide for agents integrating **flycal-cli** into [EmCP](https://github.com/magnum/emcp) (or any MCP host that shells out to a CLI).

- Gem / binary: `flycal`
- Repo: https://github.com/magnum/flycal-cli
- Scope: **read-only** Google Calendar (`calendar.readonly`)
- Machine catalog: [`mcp/tools.json`](mcp/tools.json) + [`mcp/README.md`](mcp/README.md)

This document describes the **recommended Mode A** integration (single Google operator account) and the CLI contracts EmCP should rely on.

---

## 1. What flycal-cli is

CLI that:

1. Authenticates one Google user via OAuth (Desktop app flow)
2. Lists calendars and searches events
3. Finds free slots against configured templates
4. Emits **text** (shell) or **JSON** (`--format json`) via a pipeline:

```text
Retriever → Aggregator → Renderer (TextRenderer | JsonRenderer)
```

It is designed so an MCP host can run `flycal … --format json` as a subprocess and parse stdout.

---

## 2. Auth model for EmCP (Mode A — preferred for now)

### Decision

**One Google identity** owned by the operator. That token unlocks **all calendars** visible to that account (owned + shared with that user). No per-calendar OAuth. No multi-tenant Google login required for the first EmCP integration.

If another person needs a calendar in EmCP, share that calendar **to the operator Google account** (read access is enough).

### How Google auth works inside flycal

| File | Role |
| --- | --- |
| `~/.flycal/credentials.json` | Google Cloud OAuth **client** (Desktop app JSON) |
| `~/.flycal/tokens.yml` | Persisted **user** tokens (refresh token) after `flycal login` |
| `~/.flycal/config.yml` | App config (default calendar, slots templates, locale, …) |

Flow:

1. Operator runs `flycal login` once (browser + `http://127.0.0.1:9292/oauth2callback`) **or** pastes/copies an already-exported token store into EmCP storage.
2. Later invocations only need a valid refresh token on disk; flycal refreshes the access token automatically.
3. EmCP MCP clients authenticate to EmCP (ApiKey / OAuth 2.1) — **not** to Google on every tool call.

### EmCP responsibilities (Mode A)

Mirror the [googleworkspace](https://github.com/magnum/emcp/blob/main/servers/googleworkspace/README.md) pattern:

1. Install `flycal` on the host (gem / PATH inside the app container).
2. Persist operator credentials under EmCP storage, e.g. `storage/mcp/flycal/` or `data/flycal/`:
   - `credentials.json` (OAuth client)
   - `tokens.yml` (user refresh token)
   - optional `config.yml`
3. When spawning `flycal`, point its home/config at that directory (e.g. set `HOME` or a future dedicated env if added; today flycal reads `~/.flycal` via `File.expand_path("~/.flycal")`).
4. Operator UI: `/servers/flycal/auth` — document “run login once / paste tokens”, prefer **refresh token** persistence, avoid short-lived access tokens alone.
5. Do **not** expose interactive tools (`login`, `logout`, `config`) as MCP tools unless a TTY is available.

### What Mode A does *not* do

- Multiple end-users each seeing **their own** Google calendars (that would be Mode B: web OAuth + per-EmCP-user token stores).

---

## 3. Suggested EmCP tool surface

Expose non-interactive, read-only tools. Prefer `--format json` for structured MCP results.

| MCP tool (suggested) | CLI | Notes |
| --- | --- | --- |
| `flycal_search` | `flycal search … --format json` | Primary |
| `flycal_slots` | `flycal slots …` | Free ranges; clipboard side-effect on host is OK to ignore |
| `flycal_calendars` | `flycal calendars` | Name + id lines |
| `flycal_version` | `flycal version` | Health check |

Skip / keep operator-only: `login`, `logout`, `config`, `update`.

Build argv from [`mcp/tools.json`](mcp/tools.json) (`command.argv_template` + `option_map`). Keep the catalog in sync when adding flags.

---

## 4. Global CLI options

| Flag | Default | Notes |
| --- | --- | --- |
| `--locale` | config / `en` | `en` \| `it` |
| `--format` | `text` | `text` \| `json` (search pipeline; use `json` from EmCP) |

---

## 5. `flycal search` (core for EmCP)

### Purpose

Fetch events in a time window, optional text filter, aggregate into groups, render text or JSON.

### Important flags

| Flag | Default | Notes |
| --- | --- | --- |
| `--calendar` / `-c` | `calendar_default` or primary | Name substring or calendar id |
| `--from` / `-f` | today 00:00 | Absolute or relative date |
| `--to` / `-t` | today+30d 23:59 | Ignored if `--in` set |
| `--in` / `-i` | — | Duration from `--from` (overrides `--to`) |
| `--description` / `-d` | — | **Search filter only**. Case-insensitive contains on summary/description. OR terms with `\|` (also `,`) |
| `--groupBy` | auto | See §5.1 |
| Mock flags | — | See §7 (tests / offline); usually off in EmCP prod |

### 5.1 `--groupBy`

| Value | Behavior |
| --- | --- |
| *(omitted)* | Auto from search window length: ≤7d → `day`, ≤30d → `week`, >30d → `month` |
| `day` / `week` / `month` | Force that time grouping |
| **any other string** | Mode `string`: split value on `\|` (and `,`), one group per term; match term case-insensitively in event summary/description |

**Separation of concerns:**

- `--description` → which events are **retrieved**
- `--groupBy "rui|solver"` → how retrieved events are **bucketed** (independent of `--description`)

Examples:

```bash
flycal search --calendar "Work" --from 2026-01-01 --to 2026-01-31 --format json
flycal search -d "rui|solver" --format json
flycal search --groupBy "rui|solver" --format json
flycal search -d "meeting" --groupBy week --format json
flycal search --groupBy day --from 2026-01-01 --to 2026-03-31 --format json
```

### 5.2 JSON output contract (`--format json`)

Pretty-printed JSON object:

```json
{
  "params": {
    "command": "search",
    "from": "2026-01-01T00:00:00+01:00",
    "to": "2026-01-31T23:59:59+01:00",
    "calendar": "…",
    "calendar_ids": ["…"],
    "description": "…",
    "format": "json",
    "locale": "en",
    "group_by": "week|day|month|string",
    "group_by_option": "…",
    "use_mock": false
  },
  "info": {
    "events_found": 12,
    "from": "…",
    "to": "…",
    "total_hours": 48.0,
    "total_working_days": 6.0
  },
  "items": [ /* all matched events */ ],
  "groups": [ /* aggregation buckets */ ]
}
```

**Datetimes** (params, info, group boundaries, event `start.dateTime` / `end.dateTime`): Google-style ISO-8601, e.g. `2026-07-29T14:41:00+00:00` (not `YYYYMMDDTHHMMSS`).

**Event objects** (items / group items) — Calendar-API-inspired:

```json
{
  "summary": "…",
  "description": "…",
  "start": { "dateTime": "2026-01-02T12:00:00+01:00" },
  "end": { "dateTime": "2026-01-02T16:00:00+01:00" },
  "calendarId": "…",
  "calendarSummary": "…"
}
```

All-day events use `"start": { "date": "YYYY-MM-DD" }` instead of `dateTime` when applicable.

**Groups:**

- Time modes (`day` / `week` / `month`): each group has `type`, `key`, `index`, `from`, `to` (ISO-8601), totals, `items`. No `string` key.
- String mode: each group has `type: "string"`, `string: "<term>"`, totals, `items`. No `from` / `to`.

Working day metric assumes **8 hours** per working day.

### 5.3 Pipeline internals (for debugging)

| Layer | Role |
| --- | --- |
| `Pipeline::Retriever` | Load/normalize events (Google or mock service) |
| `Pipeline::Aggregator` | Totals + `groups` (`group_by` resolution) |
| `Pipeline::TextRenderer` / `JsonRenderer` | Format stdout |
| `Pipeline::Params` | Mutable bag of CLI + derived fields across layers |
| `DescriptionQuery` | Split/match OR and string-group terms |

---

## 6. Other commands EmCP may wrap

### `flycal calendars`

Lists `name id` (one per line). Use to populate calendar pickers / resolve names to ids.

### `flycal slots`

Finds continuous free ranges using `slots.templates` in config (`work`, `dinner`, …), `free_before` / `free_after`, and busy calendars from `slots.exclude_calendars` (fallback `calendar_default`).

Key flags: `--duration`, `--from`, `--in`, `--template` / `-T`, `--calendar`.

Output is text-oriented (header + availability). Prefer documenting text parsing or extend flycal later with `--format json` for slots if EmCP needs structured slots.

### `flycal version`

`flycal 0.x.y` — useful health check after deploy.

---

## 7. Mock mode (tests / CI — optional in EmCP)

Triggered by `--mockCalendar` or `--mockTemplate` (skips Google + login).

- Templates: `mocks/<name>.json` or `mockTemplates/<name>.json`
- Required in template or CLI: `mockCalendar` plus generation window/count/patterns/hours/durations
- `--mockSeed` for reproducibility (printed in text summary / JSON `info.mock_seed`)

Search `--from`/`--to` stay normal defaults (today → +30d) unless passed; they must **overlap** the mock generation window or you get zero events.

Useful for EmCP integration tests without Google credentials.

---

## 8. Dates and durations

- Absolute: `YYYY-MM-DD`, locale variants, optional time
- Relative: `now`, `today`/`oggi`, `tomorrow`/`domani`, `monday`/`lunedi`, `next monday`/`prossimo lunedi`, …
- Durations: `30days`, `1 week`, `2months`, `45min`, `4h`, …

See `shared_formats` in `mcp/tools.json`.

---

## 9. Recommended EmCP implementation sketch

```text
servers/flycal/
  server.rb              # STI McpServer: tools + auth form
  flycal_client.rb       # spawn flycal with env/cwd/config dir
  README.md              # operator docs (login / token paste)
```

Tool handler pattern:

1. Validate MCP args against catalog schema
2. Ensure tokens file present → else return clear “operator must auth” error
3. Build argv: `["flycal", "search", …, "--format", "json"]`
4. `Open3.capture` with timeout
5. On success: parse JSON stdout, return as MCP structured/text content
6. On failure: return stderr + exit status

Auth form pattern (Mode A):

- Paste or upload `credentials.json` + `tokens.yml` **or** instructions to run `flycal login` on a machine and copy `~/.flycal/`
- Prefer refresh-token file; discourage bare access tokens

---

## 10. Security notes

- Calendar scope is **read-only**
- Treat `tokens.yml` / OAuth client JSON as secrets (EmCP encrypted columns + `storage/` volume, mode `0600`)
- MCP ApiKey/OAuth protects who can call tools; Google token protects which calendars are readable
- Mock mode must not be the default on production endpoints

---

## 11. Quick reference — Mode A checklist

- [ ] Gem `flycal-cli` installed on EmCP host
- [ ] Operator Google account has access to all needed calendars (share if needed)
- [ ] `credentials.json` + `tokens.yml` persisted under EmCP storage
- [ ] MCP tools call `flycal … --format json` (for search)
- [ ] EmCP client auth = ApiKey/OAuth EmCP (unchanged)
- [ ] Interactive `flycal login` only in operator onboarding, not as MCP tool

---

## 12. Out of scope for this brief (future)

- Mode B multi-user Google OAuth (web redirect, per-user token stores)
- JSON renderer for `slots`
- Invoking flycal as an in-process Ruby library instead of CLI (possible later; today EmCP should treat it as a binary)

When in doubt, read `mcp/tools.json` and run:

```bash
flycal help search
flycal search --help
```
