package bench

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:time"
import "../mustache"

Tag :: struct {
	name: string,
	slug: string,
}

Nav_Item :: struct {
	url:   string,
	label: string,
}

Post :: struct {
	title:   string,
	url:     string,
	date:    string,
	year:    string,
	excerpt: string,
	author:  string,
	tags:    [dynamic]Tag,
}

Comment :: struct {
	author: string,
	date:   string,
	body:   string,
}

Page_Data :: struct {
	title:     string,
	now:       string,
	posts:     [dynamic]Post,
	comments:  [dynamic]Comment,
	nav_items: [dynamic]Nav_Item,
}

TEMPLATE_DIR :: #directory

main :: proc() {
	iterations := 250
	dump_path := ""

	i := 1
	for i < len(os.args) {
		if os.args[i] == "--dump" && i + 1 < len(os.args) {
			dump_path = os.args[i + 1]
			i += 2
		} else {
			n, ok := strconv.parse_int(os.args[i])
			if ok && n > 0 {
				iterations = n
			}
			i += 1
		}
	}

	data_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&data_arena)
	defer mem.dynamic_arena_destroy(&data_arena)

	temp_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&temp_arena)
	defer mem.dynamic_arena_destroy(&temp_arena)

	context.allocator = mem.dynamic_arena_allocator(&data_arena)
	context.temp_allocator = mem.dynamic_arena_allocator(&temp_arena)

	base := parse_file("base.html")
	page := parse_file("page.html")
	defer mustache.delete_template(&base)
	defer mustache.delete_template(&page)

	partials := make(map[string]mustache.Template)
	partials["base"] = base
	partials["post"] = parse_file("partials/post.html")
	partials["comment"] = parse_file("partials/comment.html")
	defer mustache.delete_partials(partials)

	data := generate_data()

	if dump_path != "" {
		result, err := mustache.render(page, data, partials, allocator = context.temp_allocator)
		if err != nil {
			b := mustache.body(err)
			fmt.eprintln("render error:", b.msg)
			os.exit(1)
		}
		werr := os.write_entire_file_from_string(dump_path, result)
		if werr != nil {
			fmt.eprintln("failed to write", dump_path, ":", werr)
			os.exit(1)
		}
		fmt.println("wrote", len(result), "bytes to", dump_path)
		return
	}

	for _ in 0..<3 {
		_, _ = mustache.render(page, data, partials, allocator = context.temp_allocator)
		mem.dynamic_arena_free_all(&temp_arena)
	}

	start := time.now()
	for _ in 0..<iterations {
		_, _ = mustache.render(page, data, partials, allocator = context.temp_allocator)
		mem.dynamic_arena_free_all(&temp_arena)
	}
	elapsed := time.since(start)

	seconds := time.duration_seconds(elapsed)
	per_render_ms := seconds * 1000 / f64(iterations)

	fmt.printfln("iterations=%d  total=%.3fs  per_render=%.3fms",
		iterations, seconds, per_render_ms)
}

parse_file :: proc(name: string) -> mustache.Template {
	path := fmt.aprintf("%s/templates/%s", TEMPLATE_DIR, name)
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		fmt.eprintln("failed to read", path, ":", err)
		os.exit(1)
	}
	source := string(data)
	tmpl, perr := mustache.parse(source, path)
	if perr != nil {
		b := mustache.body(perr)
		fmt.eprintln("parse error in", path, ":", b.msg)
		os.exit(1)
	}
	return tmpl
}

generate_data :: proc() -> Page_Data {
	years := []string{
		"2025", "2024", "2023", "2022", "2021",
		"2020", "2019", "2018", "2017", "2016",
	}

	posts := make([dynamic]Post, 0, 500)
	for year in years {
		for i in 0..<50 {
			tags := make([dynamic]Tag, 0, 3)
			append(&tags, Tag{name = fmt.aprintf("%s-notes", year), slug = fmt.aprintf("%s-notes", year)})
			append(&tags, Tag{name = "writing", slug = "writing"})
			append(&tags, Tag{name = "archive", slug = "archive"})

			month := (i % 12) + 1
			day := (i % 28) + 1

			author := ""
			if i % 3 != 0 {
				author = fmt.aprintf("Author %d", i % 5)
			}

			append(&posts, Post{
				title = fmt.aprintf("Post %d from %s", i, year),
				url = fmt.aprintf("/%s/post-%d", year, i),
				date = fmt.aprintf("%s-%02d-%02dT10:00:00Z", year, month, day),
				year = year,
				excerpt = "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
				author = author,
				tags = tags,
			})
		}
	}

	comments := make([dynamic]Comment, 0, 100)
	for i in 0..<100 {
		year := years[i % len(years)]
		month := (i % 12) + 1
		day := (i % 28) + 1
		append(&comments, Comment{
			author = fmt.aprintf("Commenter %d", i),
			date = fmt.aprintf("%s-%02d-%02dT12:00:00Z", year, month, day),
			body = fmt.aprintf("Great post! This is comment number %d.", i),
		})
	}

	nav_items := make([dynamic]Nav_Item, 0, 8)
	append(&nav_items, Nav_Item{url = "/", label = "Home"})
	append(&nav_items, Nav_Item{url = "/archive", label = "Archive"})
	append(&nav_items, Nav_Item{url = "/about", label = "About"})
	append(&nav_items, Nav_Item{url = "/tags", label = "Tags"})
	append(&nav_items, Nav_Item{url = "/feed.xml", label = "RSS"})
	append(&nav_items, Nav_Item{url = "https://github.com/example", label = "GitHub"})
	append(&nav_items, Nav_Item{url = "https://twitter.com/example", label = "Twitter"})
	append(&nav_items, Nav_Item{url = "mailto:nobody@example.com", label = "Email"})

	return Page_Data{
		title = "Post Archive",
		now = "2025-07-21T12:00:00Z",
		posts = posts,
		comments = comments,
		nav_items = nav_items,
	}
}
