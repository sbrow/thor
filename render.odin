package main

import "core:fmt"
import "core:os"
import "core:strings"

SITE_TITLE :: "One Idiot Developer"
SITE_DESC :: "This is fine...right?"

@(rodata)
MONTHS: [12]string = {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

CSS :: `
body { background: #020617; color: #e2e8f0; font-family: system-ui, sans-serif; max-width: 720px; margin: 0 auto; padding: 2rem; line-height: 1.6; }
a { color: #7dd3fc; }
h1, h2, h3 { color: #f1f5f9; line-height: 1.3; }
nav { display: flex; gap: 1rem; margin-bottom: 2rem; padding-bottom: 1rem; border-bottom: 1px solid #1e293b; }
pre { background: #1e293b; padding: 1rem; border-radius: 0.5rem; overflow-x: auto; }
code { font-family: monospace; font-size: 0.9em; }
p code { background: #1e293b; padding: 0.1em 0.3em; border-radius: 0.25em; }
blockquote { border-left: 4px solid #475569; margin: 0; padding: 0.5rem 0 0.5rem 1rem; color: #94a3b8; }
img { max-width: 100%; }
hr { border: none; border-top: 1px solid #1e293b; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #334155; padding: 0.5rem; }
`

NAV :: `
<nav>
  <a href="/">Home</a>
  <a href="/posts/">Posts</a>
  <a href="/ideas/">Ideas</a>
</nav>
`

render_site :: proc(pages: []Page, output_dir: string) {
	sort_pages_by_date(pages)

	for page in pages {
		html := render_page_html(page)
		write_page(output_dir, page.permalink, html)
	}

	home_html := render_home_html(pages)
	write_file(fmt.tprintf("%s/index.html", output_dir), home_html)

	posts_html := render_posts_html(pages)
	write_page(output_dir, "/posts/", posts_html)

	fmt.printfln("Rendered %d pages to %s", len(pages) + 2, output_dir)
}

render_page_html :: proc(page: Page) -> string {
	body := fmt.aprintf(
		`<main>
  <article>
    <h1>%s</h1>
%s    %s
  </article>
</main>
`,
		page.title,
		render_date(page),
		page.body_html,
	)
	title := fmt.tprintf("%s | %s", page.title, SITE_TITLE)
	return render_chrome(title, body)
}

render_home_html :: proc(pages: []Page) -> string {
	items: [dynamic]string
	defer delete(items)

	for page in pages {
		append(&items, render_post_item(page))
	}

	post_list := strings.join(items[:], "\n")

	body := fmt.aprintf(
		`<main>
  <header>
    <h1>%s</h1>
    <p>%s</p>
  </header>
  <ul>
%s
  </ul>
</main>
`,
		SITE_TITLE,
		SITE_DESC,
		post_list,
	)

	return render_chrome(SITE_TITLE, body)
}

render_posts_html :: proc(pages: []Page) -> string {
	parts: [dynamic]string
	defer delete(parts)

	append(&parts, "<main>\n  <h1>Posts</h1>\n")

	current_year := ""
	open := false
	for page in pages {
		if page.type != .Post {
			continue
		}
		year := get_year(page.date)
		if year != current_year {
			if open {
				append(&parts, "  </ul>\n")
			}
			open = true
			current_year = year
			append(&parts, fmt.aprintf("  <h2>%s</h2>\n  <hr>\n  <ul>\n", year))
		}
		append(&parts, render_post_item(page))
		append(&parts, "\n")
	}
	if open {
		append(&parts, "  </ul>\n")
	}
	append(&parts, "</main>\n")

	body := strings.join(parts[:], "")
	title := fmt.tprintf("Posts | %s", SITE_TITLE)
	return render_chrome(title, body)
}

render_chrome :: proc(page_title: string, body: string) -> string {
	return fmt.aprintf(
		`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>%s</title>
  <style>%s</style>
</head>
<body>
%s%s
</body>
</html>
`,
		page_title,
		CSS,
		NAV,
		body,
	)
}

render_post_item :: proc(page: Page) -> string {
	date_html := ""
	if page.date != "" {
		date_html = fmt.aprintf(" <time>%s</time>", format_date(page.date))
	}
	star := ""
	if page.is_starred {
		star = " \xe2\x98\x85"
	}
	return fmt.aprintf(
		`    <li><a href="%s">%s</a>%s%s</li>`,
		page.permalink,
		page.title,
		date_html,
		star,
	)
}

render_date :: proc(page: Page) -> string {
	if page.date == "" {
		return ""
	}
	return fmt.aprintf(`    <time datetime="%s">%s</time>` + "\n", page.date, format_date(page.date))
}

format_date :: proc(iso: string) -> string {
	if len(iso) < 10 {
		return iso
	}
	year := iso[:4]
	month_num := (int(iso[5]) - 0x30) * 10 + (int(iso[6]) - 0x30)
	day_num := (int(iso[8]) - 0x30) * 10 + (int(iso[9]) - 0x30)

	if month_num < 1 || month_num > 12 {
		return iso[:10]
	}

	return fmt.aprintf("%d %s %s", day_num, MONTHS[month_num - 1], year)
}

get_year :: proc(iso: string) -> string {
	if len(iso) < 4 {
		return ""
	}
	return iso[:4]
}

sort_pages_by_date :: proc(pages: []Page) {
	for i in 1..<len(pages) {
		key := pages[i]
		j := i - 1
		for j >= 0 && pages[j].date < key.date {
			pages[j + 1] = pages[j]
			j -= 1
		}
		pages[j + 1] = key
	}
}

write_page :: proc(output_dir: string, permalink: string, html: string) {
	rel := permalink
	if len(rel) > 0 && rel[0] == '/' {
		rel = rel[1:]
	}

	dir := fmt.tprintf("%s/%s", output_dir, rel)
	if err := os.make_directory_all(dir); err != nil && err != .Exist {
		fmt.eprintfln("thor: cannot create %s: %v", dir, err)
		return
	}

	file_path := fmt.tprintf("%s/index.html", dir)
	write_file(file_path, html)
}

write_file :: proc(path: string, html: string) {
	if err := os.write_entire_file_from_string(path, html); err != nil {
		fmt.eprintfln("thor: cannot write %s: %v", path, err)
	}
}
