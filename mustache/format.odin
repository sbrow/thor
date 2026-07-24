package mustache

import "core:fmt"
import "core:log"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"

Date_Components :: struct {
	year:           int,
	month:          int,
	day:            int,
	hour:           int,
	minute:         int,
	second:         int,
	offset_seconds: int,
	has_offset:     bool,
	tz_abbr:        string,
}

// TODO: Use some kind of scanner interface
parse_iso_date :: proc(iso: string) -> (c: Date_Components, ok: bool) {
	if len(iso) < 10 {
		return {}, false
	}

	c.year = parse_2_digits(iso, 0) * 100 + parse_2_digits(iso, 2)
	c.month = parse_2_digits(iso, 5)
	c.day = parse_2_digits(iso, 8)

	if c.month < 1 || c.month > 12 {
		return {}, false
	}
	if c.day < 1 || c.day > 31 {
		return {}, false
	}

	if len(iso) >= 19 && (iso[10] == 'T' || iso[10] == 't') {
		c.hour = parse_2_digits(iso, 11)
		c.minute = parse_2_digits(iso, 14)
		c.second = parse_2_digits(iso, 17)
	}

	parse_offset(iso, &c)

	c.tz_abbr = "UTC"
	return c, true
}

parse_2_digits :: proc(s: string, offset: int) -> int {
	if offset + 1 >= len(s) {
		return 0
	}
	return (int(s[offset]) - 0x30) * 10 + (int(s[offset + 1]) - 0x30)
}

// parse_offset parses the timezone suffix of an ISO 8601 string (Z,
// +HH:MM, +HHMM, -HH:MM, -HHMM). Skips fractional seconds if present.
// Does nothing if no recognizable offset is found.
parse_offset :: proc(iso: string, c: ^Date_Components) {
	pos := 19
	if pos >= len(iso) {
		return
	}

	// Skip fractional seconds (e.g., .123)
	if iso[pos] == '.' {
		pos += 1
		for pos < len(iso) && iso[pos] >= '0' && iso[pos] <= '9' {
			pos += 1
		}
	}

	if pos >= len(iso) {
		return
	}

	switch iso[pos] {
	case 'Z', 'z':
		c.has_offset = true
	case '+', '-':
		sign := 1 if iso[pos] == '+' else -1
		pos += 1
		if pos + 1 >= len(iso) {
			return
		}
		hours := parse_2_digits(iso, pos)
		pos += 2

		minutes := 0
		if pos < len(iso) && iso[pos] == ':' {
			pos += 1
		}
		if pos + 1 < len(iso) {
			minutes = parse_2_digits(iso, pos)
		}

		c.offset_seconds = sign * (hours * 3600 + minutes * 60)
		c.has_offset = true
	case:
	// no recognizable offset
	}
}

format_date :: proc(
	dt: Date_Components,
	fmt: string,
	allocator := context.temp_allocator,
) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)

	for i := 0; i < len(fmt); {
		matched := match_token(&b, dt, fmt[i:])
		if matched > 0 {
			i += matched
		} else {
			strings.write_byte(&b, fmt[i])
			i += 1
		}
	}

	log.debugf("formatted date: '%s'", b.buf)
	return strings.to_string(b)
}

match_token :: proc(b: ^strings.Builder, dt: Date_Components, s: string) -> int {
	if strings.has_prefix(
		s,
		"January",
	) {strings.write_string(b, fmt.tprintf("%s", time.Month(dt.month))); return 7}
	if strings.has_prefix(s, "Monday") {emit_weekday(b, dt, full = true); return 6}
	if strings.has_prefix(
		s,
		"2006",
	) {strings.write_string(b, fmt.tprintf("%04d", dt.year)); return 4}
	if strings.has_prefix(s, "MST") {
		abbr := dt.tz_abbr
		if len(abbr) == 0 do abbr = "UTC"
		strings.write_string(b, abbr)
		return 3
	}
	if strings.has_prefix(s, "Jan") {emit_month_abbr(b, dt); return 3}
	if strings.has_prefix(s, "Mon") {emit_weekday(b, dt, full = false); return 3}
	if strings.has_prefix(
		s,
		"06",
	) {strings.write_string(b, fmt.tprintf("%02d", dt.year % 100)); return 2}
	if strings.has_prefix(s, "02") {strings.write_string(b, fmt.tprintf("%02d", dt.day)); return 2}
	if strings.has_prefix(
		s,
		"15",
	) {strings.write_string(b, fmt.tprintf("%02d", dt.hour)); return 2}
	if strings.has_prefix(
		s,
		"04",
	) {strings.write_string(b, fmt.tprintf("%02d", dt.minute)); return 2}
	if strings.has_prefix(
		s,
		"05",
	) {strings.write_string(b, fmt.tprintf("%02d", dt.second)); return 2}
	if strings.has_prefix(
		s,
		"01",
	) {strings.write_string(b, fmt.tprintf("%02d", dt.month)); return 2}
	if strings.has_prefix(s, "03") {emit_hour_12(b, dt, pad = true); return 2}
	if strings.has_prefix(s, "PM") {emit_am_pm(b, dt); return 2}
	if strings.has_prefix(s, "pm") {emit_am_pm_lower(b, dt); return 2}
	if len(s) >= 1 {
		switch s[0] {
		case '2':
			strings.write_string(b, fmt.tprintf("%d", dt.day)); return 1
		case '1':
			strings.write_string(b, fmt.tprintf("%d", dt.month)); return 1
		case '4':
			strings.write_string(b, fmt.tprintf("%d", dt.minute)); return 1
		case '5':
			strings.write_string(b, fmt.tprintf("%d", dt.second)); return 1
		case '3':
			emit_hour_12(b, dt, pad = false); return 1
		case:
			return 0
		}
	}
	return 0
}

emit_month_abbr :: proc(b: ^strings.Builder, dt: Date_Components) {
	name := fmt.tprintf("%s", time.Month(dt.month))
	strings.write_string(b, name[:3 if len(name) >= 3 else len(name)])
}

emit_weekday :: proc(b: ^strings.Builder, dt: Date_Components, full: bool) {
	date := datetime.Date {
		year  = i64(dt.year),
		month = i8(dt.month),
		day   = i8(dt.day),
	}
	ordinal, err := datetime.date_to_ordinal(date)
	if err != .None {
		strings.write_string(b, "???")
		return
	}
	weekday := datetime.day_of_week(ordinal)
	name := fmt.tprintf("%s", weekday)
	if full {
		strings.write_string(b, name)
	} else {
		strings.write_string(b, name[:3 if len(name) >= 3 else len(name)])
	}
}

emit_hour_12 :: proc(b: ^strings.Builder, dt: Date_Components, pad: bool) {
	h12 := dt.hour % 12
	if h12 == 0 {h12 = 12}
	format := "%02d" if pad else "%d"

	fmt.sbprintf(b, format, h12)
}

emit_am_pm :: proc(b: ^strings.Builder, dt: Date_Components) {
	strings.write_string(b, "PM" if dt.hour >= 12 else "AM")
}

emit_am_pm_lower :: proc(b: ^strings.Builder, dt: Date_Components) {
	strings.write_string(b, "pm" if dt.hour >= 12 else "am")
}

// ---------------------------------------------------------------------------
// Timezone conversion infrastructure
// ---------------------------------------------------------------------------

format_offset :: proc(offset_seconds: int) -> string {
	if offset_seconds == 0 do return "UTC"
	sign := "+" if offset_seconds > 0 else "-"
	abs_val := abs(offset_seconds)
	hours := abs_val / 3600
	minutes := (abs_val % 3600) / 60
	return fmt.tprintf("UTC%s%02d:%02d", sign, hours, minutes)
}

// tz_cache caches loaded TZ_Region pointers by timezone name.
// Entries persist until destroy_tz_cache is called.
tz_cache: map[string]^datetime.TZ_Region

get_cached_tz :: proc(name: string) -> (^datetime.TZ_Region, bool) {
	if name == "" || name == "UTC" {
		return nil, true
	}
	if cached, ok := tz_cache[name]; ok {
		return cached, true
	}
	tz, ok := timezone.region_load(name)
	if !ok {
		return nil, false
	}
	tz_cache[name] = tz
	return tz, true
}

destroy_tz_cache :: proc() {
	for _, tz in tz_cache {
		if tz != nil {
			timezone.region_destroy(tz)
		}
	}
	delete(tz_cache)
	tz_cache = nil
}

// convert_to_tz converts date components from their source timezone to a
// target timezone.
//
// If the source has no offset (has_offset=false), the components are
// assumed to be in the target timezone — only the abbreviation is resolved.
//
// If the source has an offset, the components are first adjusted to true
// UTC, then converted to the target timezone.
//
// Precondition: target_tz != nil.
convert_to_tz :: proc(
	c: Date_Components,
	target_tz: ^datetime.TZ_Region,
) -> (
	result: Date_Components,
	ok: bool,
) {
	result = c
	dt := datetime.DateTime {
		year   = i64(c.year),
		month  = i8(c.month),
		day    = i8(c.day),
		hour   = i8(c.hour),
		minute = i8(c.minute),
		second = i8(c.second),
	}

	if !c.has_offset {
		dt.tz = target_tz
		abbr, _ := timezone.shortname(dt)
		result.tz_abbr = abbr
		return result, true
	}

	tm := time.datetime_to_time(dt) or_return

	secs := time.time_to_unix(tm) - i64(c.offset_seconds)
	tm = time.unix(secs, 0)

	dt_utc := time.time_to_datetime(tm) or_return
	dt_out := timezone.datetime_to_tz(dt_utc, target_tz) or_return

	abbr, _ := timezone.shortname(dt_out)

	return {
			year = int(dt_out.year),
			month = int(dt_out.month),
			day = int(dt_out.day),
			hour = int(dt_out.hour),
			minute = int(dt_out.minute),
			second = int(dt_out.second),
			tz_abbr = abbr,
		},
		true
}

