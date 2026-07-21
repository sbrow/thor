package mustache

import "core:fmt"
import "core:log"
import "core:strings"
import "core:time"
import "core:time/datetime"

Date_Components :: struct {
	year:   int,
	month:  int,
	day:    int,
	hour:   int,
	minute: int,
	second: int,
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

	return c, true
}

parse_2_digits :: proc(s: string, offset: int) -> int {
	if offset + 1 >= len(s) {
		return 0
	}
	return (int(s[offset]) - 0x30) * 10 + (int(s[offset + 1]) - 0x30)
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
	if strings.has_prefix(s, "MST") {strings.write_string(b, "UTC"); return 3}
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

