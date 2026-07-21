package main

import "base:runtime"
import "common"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:time"
import "inlined"
import "original"

DATES :: #load(#directory + os.Path_Separator_String + "dates.txt")
FORMATS :: #load(#directory + os.Path_Separator_String + "formats.txt")

ITERATIONS :: 1_000

dates: []common.Date_Components
formats: []string

formatter :: #type proc(
	date: common.Date_Components,
	format: string,
	allocator: runtime.Allocator,
) -> string

benchmark :: #type proc(
	options: ^time.Benchmark_Options,
	allocator: runtime.Allocator,
) -> (
	err: time.Benchmark_Error,
)

Version :: struct {
	name:  string,
	bench: benchmark,
}

init :: proc() {
	raw_dates := strings.split_lines(string(DATES))
	raw_dates = raw_dates[:len(raw_dates) - 1]
	formats = strings.split_lines(string(FORMATS))

	dates = make([]common.Date_Components, len(raw_dates))

	assert(to_parsed(raw_dates, &dates))
}

to_parsed :: proc(raw_dates: []string, dates: ^[]common.Date_Components) -> bool {
	for date, i in raw_dates {
		// log.debugf("parsing '%s'", date)
		dates[i] = common.parse_iso_date(date) or_return
	}

	return true
}

main :: proc() {
	logger_opts: log.Options =
		(log.Default_Console_Logger_Opts - log.Full_Timestamp_Opts - {.Short_File_Path})
	console_logger := log.create_console_logger(.Info, logger_opts)
	context.logger = console_logger
	defer log.destroy_console_logger(console_logger)

	init()

	versions := [?]Version {
		{"original", to_benchmark(original.format_date)},
		{"inlined", to_benchmark(inlined.format_date)},
	}

	fmt.printfln(
		"%-10s %14s %10s %14s %12s %8s",
		"version",
		"total",
		"calls",
		"calls/s",
		"time/call",
		"MB/s",
	)

	for version in versions {
		defer free_all(context.temp_allocator)

		b: time.Benchmark_Options
		b.bench = version.bench

		if err := time.benchmark(&b, context.temp_allocator); err != nil {
			fmt.panicf("%v", err)
		}

		// fmt.printfln("%v", b)
		per_call := time.Duration(i64(b.duration) / i64(b.count))
		fmt.printfln(
			"%-10s %14v % 10d % 14.0f %12v % 8.2f",
			version.name,
			b.duration,
			b.count,
			b.rounds_per_second,
			per_call,
			b.megabytes_per_second,
		)
	}
}

to_benchmark :: proc($f: formatter) -> benchmark {
	return(
		proc(
			opts: ^time.Benchmark_Options,
			allocator: runtime.Allocator,
		) -> (
			err: time.Benchmark_Error,
		) {
			for _ in 0 ..< ITERATIONS {
				for date in dates {
					for format in formats {
						f(date, format, allocator)
						opts.count += 1
						opts.processed += size_of(date) + size_of(format)
					}
				}

				opts.rounds += 1
			}

			return err
		} \
	)
}

