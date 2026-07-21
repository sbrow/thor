package main

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

