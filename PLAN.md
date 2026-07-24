# Timezone Support

## Goal

Add timezone conversion to the `format` pipe so dates display in the configured site timezone, with correct abbreviations for the `MST` token.

## Context

Dates are stored as raw ISO 8601 strings. The `format` pipe formats them for display using Go-style layout tokens. Currently `parse_iso_date` ignores the timezone offset suffix, and `MST` is hardcoded to `"UTC"`.

Pipes now take `ctx: []any`, so timezone config can flow through the data context identically to `date_format` — no new parameters to thread.

## Decisions

- **MST fallback** (no target tz, date has offset): `UTC-04:00` format
- **`now` field**: intentionally UTC (offset=0). The `format` pipe handles timezone display.
- **TZ_Region cache**: lives in the mustache package (`format.odin`)

## Files changed

| File | Changes |
|---|---|
| `mustache/format.odin` | Extend `Date_Components` (+`offset_seconds`, `has_offset`, `tz_abbr`). Extend `parse_iso_date` to parse trailing offset. Add `tz_cache`, `get_cached_tz`, `convert_to_tz`, `format_offset`, `destroy_tz_cache`. Fix MST token. Import `core:time/timezone`. |
| `mustache/pipes.odin` | Resolve `date_timezone` from ctx in `"format"` case (optional — nil is fine). Add `timezone_name` param to `apply_format`. Orchestrates parse → convert → format. |
| `render.odin` | Add `date_timezone: string` to `Base_Data`, populate from `site.date.timezone`. Remove `// TODO: CAlculate offset` (offset=0 is intentional — UTC). |
| `site.odin` | Call `mustache.destroy_tz_cache()` from `destroy_site`. No structural changes — `Date_Preferences.timezone` already exists and flows through config. |
| `mustache/pipes_test.odin` | Add `date_timezone: string` to test data structs. Add timezone conversion tests. |

## Conversion logic (in `apply_format`)

```
1. parse_iso_date(iso) → components (now includes offset_seconds, has_offset)
2. tz_name := resolve "date_timezone" from ctx (optional)
3. target_tz := get_cached_tz(tz_name)   // nil if empty/UTC/not configured
4. if target_tz != nil:
       components = convert_to_tz(components, target_tz)
       // tz_abbr filled by convert_to_tz via timezone.shortname()
5. else if components.has_offset:
       components.tz_abbr = format_offset(components.offset_seconds)
       // e.g. "UTC-04:00"
6. else:
       components.tz_abbr = "UTC"
7. format_date(components, fmt)
```

## `convert_to_tz` flow

```
1. Build DateTime from components (tz=nil=UTC)
2. If has_offset: add offset_seconds to get true UTC
3. timezone.datetime_to_tz(utc_dt, target_tz) → converted DateTime
4. Extract components from converted DateTime
5. tz_abbr = timezone.shortname(converted_dt)  // "EST", "EDT", etc.
```

## MST fallback: `format_offset`

```
0       → "UTC"
-14400  → "UTC-04:00"
+19800  → "UTC+05:30"
```

## `now` field

`now` stays UTC (offset=0). Remove the `// TODO: CAlculate offset` comment — it's correct as-is. Templates format it with `{{now | format}}` and the pipe handles timezone display.

## Behavior matrix

| Config TZ | ISO has offset | Conversion | `MST` output |
|---|---|---|---|
| `"America/New_York"` | yes (`-04:00`) | UTC → NY (DST-aware) | `"EST"`/`"EDT"` |
| `"America/New_York"` | no | assume already in NY | `"EST"`/`"EDT"` |
| not set | yes (`-04:00`) | none — display as-is | `"UTC-04:00"` |
| not set | no | none | `"UTC"` |

## Imports added

- `mustache/format.odin`: `import "core:time/timezone"` (for `region_load`, `datetime_to_tz`, `shortname`, `region_destroy`)

## Odin timezone API reference

- `timezone.region_load(name: string) -> (^datetime.TZ_Region, bool)` — `"local"` reads `$TZ` env, falls back to `/etc/localtime`
- `timezone.region_destroy(region: ^datetime.TZ_Region)`
- `timezone.datetime_to_tz(dt: DateTime, tz: ^TZ_Region) -> (DateTime, bool)` — DST-aware. If `dt.tz == tz`, no-op. If `dt.tz == nil`, treats as UTC.
- `timezone.shortname(dt: DateTime) -> (string, bool)` — abbreviation from TZ_Region records (e.g. `"EST"`, `"EDT"`)
- `datetime.DateTime :: struct { using date: Date, using time: Time, tz: ^TZ_Region }` — `tz == nil` means UTC
