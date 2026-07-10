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

HEADER :: `
<header>
  <nav>
    <ul>
      <li class="mr-auto"><a href="/">Home</a></li>
      <li><a href="/ideas/">Ideas</a></li>
      <li><a href="/posts/">Posts</a></li>
    </ul>
  </nav>
</header>
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
  <article class="prose">
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
  <header class="text-center mb-28">
    <img class="mx-auto w-18 h-18 rounded-full" src="/avatar.jpg">
    <h1 class="text-2xl/12 mt-2.5 mb-0 font-bold">%s</h1>
    <p class="text-slate-400">%s</p>
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

	append(&parts, "<main>\n")
	append(&parts, `  <h1 class="text-center">Posts</h1>` + "\n")

	current_year := ""
	open := false
	for page in pages {
		if page.type != .Post {
			continue
		}
		year := get_year(page.date)
		if year != current_year {
			if open {
				append(&parts, "    </ul>\n  </section>\n")
			}
			open = true
			current_year = year
			append(
				&parts,
				fmt.aprintf("  <section>\n    <h2>%s</h2>\n    <hr class=\"text-slate-800 mb-1\">\n    <ul>\n", year),
			)
		}
		append(&parts, render_post_item(page))
		append(&parts, "\n")
	}
	if open {
		append(&parts, "    </ul>\n  </section>\n")
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
  <link rel="stylesheet" href="/css/main.css">
</head>
<body>
%s%s<footer>
  <a href="https://github.com/sbrow" target="_blank" rel="noopener noreferrer me" title="Github">GitHub</a>
  <a href="/index.xml" target="_blank" rel="noopener noreferrer me" title="Rss">RSS</a>
  <p class="pt-5 prose">Proudly built with <a href="https://odin-lang.org/">Odin</a></p>
  <p><small>&copy;</small> 2026</p>
</footer>
</body>
</html>
`,
		page_title,
		HEADER,
		body,
	)
}

render_post_item :: proc(page: Page) -> string {
	date_html := ""
	if page.date != "" {
		date_html = fmt.aprintf(
			"<time datetime=\"%s\">%s</time>",
			page.date,
			format_date(page.date),
		)
	}
	star := ""
	if page.is_starred {
		star = `<span class="text-yellow-500 mr-2">★</span>`
	}
	return fmt.aprintf(
		`      <li class="flex justify-between"><a href="%s">%s</a><span>%s%s</span></li>`,
		page.permalink,
		page.title,
		star,
		date_html,
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
