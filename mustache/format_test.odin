#+test
package mustache

import "core:testing"

// ---------------------------------------------------------------------------
// parse_iso_date
// ---------------------------------------------------------------------------

@(test)
test_parse_iso_date_extracts_time :: proc(t: ^testing.T) {
	c, ok := parse_iso_date("2026-03-15T08:49:54-04:00")
	testing.expect(t, ok, "should parse")
	testing.expect_value(t, c.year, 2026)
	testing.expect_value(t, c.month, 3)
	testing.expect_value(t, c.day, 15)
	testing.expect_value(t, c.hour, 8)
	testing.expect_value(t, c.minute, 49)
	testing.expect_value(t, c.second, 54)
}

@(test)
test_parse_iso_date_lowercase_t :: proc(t: ^testing.T) {
	c, ok := parse_iso_date("2026-03-15t08:49:54Z")
	testing.expect(t, ok, "should parse lowercase t separator")
	testing.expect_value(t, c.hour, 8)
	testing.expect_value(t, c.minute, 49)
	testing.expect_value(t, c.second, 54)
}

@(test)
test_parse_iso_date_date_only_zero_time :: proc(t: ^testing.T) {
	c, ok := parse_iso_date("2026-03-15")
	testing.expect(t, ok, "should parse date-only")
	testing.expect_value(t, c.hour, 0)
	testing.expect_value(t, c.minute, 0)
	testing.expect_value(t, c.second, 0)
}

@(test)
test_parse_iso_date_invalid_day_errors :: proc(t: ^testing.T) {
	_, ok := parse_iso_date("2026-03-32")
	testing.expect(t, !ok, "day > 31 should fail")
}

@(test)
test_parse_iso_date_too_short_errors :: proc(t: ^testing.T) {
	_, ok := parse_iso_date("2026-03")
	testing.expect(t, !ok, "input shorter than 10 chars should fail")
}

// ---------------------------------------------------------------------------
// format_date / match_token
// ---------------------------------------------------------------------------

@(test)
test_format_date_weekday_full :: proc(t: ^testing.T) {
	// 2026-01-01 is a Thursday.
	dt := Date_Components{year = 2026, month = 1, day = 1}
	result := format_date(dt, "Monday")
	testing.expect_value(t, result, "Thursday")
}

@(test)
test_format_date_weekday_abbr :: proc(t: ^testing.T) {
	dt := Date_Components{year = 2026, month = 1, day = 1}
	result := format_date(dt, "Mon")
	testing.expect_value(t, result, "Thu")
}

@(test)
test_format_date_month_full_name :: proc(t: ^testing.T) {
	dt := Date_Components{year = 2026, month = 3, day = 15}
	result := format_date(dt, "January")
	testing.expect_value(t, result, "March")
}

@(test)
test_format_date_two_digit_year :: proc(t: ^testing.T) {
	dt := Date_Components{year = 2026, month = 3, day = 15}
	result := format_date(dt, "06")
	testing.expect_value(t, result, "26")
}

@(test)
test_format_date_hour24_padded :: proc(t: ^testing.T) {
	midnight := Date_Components{year = 2026, month = 1, day = 1, hour = 0}
	testing.expect_value(t, format_date(midnight, "15"), "00")

	afternoon := Date_Components{year = 2026, month = 1, day = 1, hour = 13}
	testing.expect_value(t, format_date(afternoon, "15"), "13")
}

@(test)
test_format_date_hour12_padded_am_pm_boundaries :: proc(t: ^testing.T) {
	cases := [4]struct {
		hour:     int,
		expected: string,
	}{{0, "12 AM"}, {12, "12 PM"}, {13, "01 PM"}, {23, "11 PM"}}

	for &c in cases {
		dt := Date_Components{year = 2026, month = 1, day = 1, hour = c.hour}
		result := format_date(dt, "03 PM")
		testing.expect_value(t, result, c.expected)
	}
}

@(test)
test_format_date_hour12_unpadded :: proc(t: ^testing.T) {
	one_am := Date_Components{year = 2026, month = 1, day = 1, hour = 1}
	testing.expect_value(t, format_date(one_am, "3"), "1")

	one_pm := Date_Components{year = 2026, month = 1, day = 1, hour = 13}
	testing.expect_value(t, format_date(one_pm, "3"), "1")
}

@(test)
test_format_date_am_pm_lowercase :: proc(t: ^testing.T) {
	afternoon := Date_Components{year = 2026, month = 1, day = 1, hour = 13}
	testing.expect_value(t, format_date(afternoon, "pm"), "pm")

	morning := Date_Components{year = 2026, month = 1, day = 1, hour = 9}
	testing.expect_value(t, format_date(morning, "pm"), "am")
}

@(test)
test_format_date_minute_second_padding :: proc(t: ^testing.T) {
	dt := Date_Components{year = 2026, month = 1, day = 1, minute = 4, second = 5}
	testing.expect_value(t, format_date(dt, "04:05"), "04:05")
	testing.expect_value(t, format_date(dt, "4:5"), "4:5")
}

@(test)
test_format_date_month_day_numeric_padding :: proc(t: ^testing.T) {
	dt := Date_Components{year = 2026, month = 3, day = 5}
	testing.expect_value(t, format_date(dt, "01"), "03")
	testing.expect_value(t, format_date(dt, "1"), "3")
	testing.expect_value(t, format_date(dt, "02"), "05")
	testing.expect_value(t, format_date(dt, "2"), "5")
}

@(test)
test_format_date_mst_always_utc :: proc(t: ^testing.T) {
	// Date_Components carries no offset yet, so MST is a hardcoded
	// placeholder until real timezone support lands.
	dt := Date_Components{year = 2026, month = 1, day = 1, hour = 12}
	result := format_date(dt, "MST")
	testing.expect_value(t, result, "UTC")
}

@(test)
test_format_date_literal_passthrough :: proc(t: ^testing.T) {
	dt := Date_Components{year = 2026, month = 1, day = 1}
	result := format_date(dt, "Year: 2006!")
	testing.expect_value(t, result, "Year: 2026!")
}

@(test)
test_format_date_combined_go_reference_layout :: proc(t: ^testing.T) {
	// 2023-10-15 is a Sunday.
	dt := Date_Components{year = 2023, month = 10, day = 15, hour = 13, minute = 18, second = 50}
	result := format_date(dt, "Mon Jan 2 15:04:05 MST 2006")
	testing.expect_value(t, result, "Sun Oct 15 13:18:50 UTC 2023")
}
