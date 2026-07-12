package main

import "core:fmt"
import "core:os"
import "core:strings"

MONTHS: [12]string = {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

render_site :: proc(pages: []Page, config: Site_Config) {
	sort_pages_by_date(pages)

	// Find home page
	home: Page
	has_home := false
	for page in pages {
		if page.type == .Home {
			home = page
			has_home = true
			break
		}
	}

	// Render individual content pages (skip home)
	for page in pages {
		if page.type == .Home {
			continue
		}
		html := render_page_html(page, config)
		write_page(config.output_dir, page.permalink, html)
	}

	// Render home page
	if has_home {
		home_html := render_home_html(home, pages, config)
		write_file(fmt.tprintf("%s/index.html", config.output_dir), home_html)
	}

	// Render posts list page
	posts_html := render_posts_html(pages, config)
	write_page(config.output_dir, "/posts/", posts_html)

	// Generate RSS feed
	rss := generate_rss(pages, config)
	write_file(fmt.tprintf("%s/index.xml", config.output_dir), rss)

	// Generate sitemap
	sitemap := generate_sitemap(pages, config.base_url)
	write_file(fmt.tprintf("%s/sitemap.xml", config.output_dir), sitemap)

	// Copy static assets (avatar, favicon, etc.)
	copy_static_assets(config.content_dir, config.output_dir)

	// Generate robots.txt
	robots := fmt.aprintf("User-agent: *\nAllow: /\nSitemap: %s/sitemap.xml\n", config.base_url)
	write_file(fmt.tprintf("%s/robots.txt", config.output_dir), robots)

	total := len(pages) + 1
	if !has_home {
		total += 1
	}
	fmt.printfln("Rendered %d pages to %s", total, config.output_dir)
}

render_page_html :: proc(page: Page, config: Site_Config) -> string {
	comments := ""
	if page.type == .Post {
		comments = `
  <script src="https://utteranc.es/client.js"
          repo="sbrow/sbrow.github.io"
          issue-term="pathname"
          label="Comment"
          theme="github-dark"
          crossorigin="anonymous"
          async></script>`
	}

	body := fmt.aprintf(
		`<main>
  <article class="prose">
    <h1>%s</h1>
%s    %s
  </article>%s
</main>
`,
		page.title,
		render_date(page),
		page.body_html,
		comments,
	)
	title := fmt.tprintf("%s | %s", page.title, config.title)
	return render_chrome(title, body, config)
}

render_home_html :: proc(home: Page, pages: []Page, config: Site_Config) -> string {
	items: [dynamic]string
	defer delete(items)

	for page in pages {
		if page.type == .Home {
			continue
		}
		append(&items, render_post_item(page))
	}

	post_list := strings.join(items[:], "\n")

	body := fmt.aprintf(
		`<main>
  <header class="text-center mb-28">
%s  </header>
  <ul>
%s
  </ul>
</main>
`,
		home.body_html,
		post_list,
	)

	return render_chrome(config.title, body, config)
}

render_posts_html :: proc(pages: []Page, config: Site_Config) -> string {
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
	title := fmt.tprintf("Posts | %s", config.title)
	return render_chrome(title, body, config)
}

render_chrome :: proc(page_title: string, body: string, config: Site_Config) -> string {
	header := fmt.aprintf(HEADER, ICON_HOME)

	// Build social links from config
	social_parts: [dynamic]string
	defer delete(social_parts)
	for link in config.social {
		append(
			&social_parts,
			fmt.aprintf(
				`\n  <a href="%s" target="_blank" rel="noopener noreferrer me" title="%s">%s</a>`,
				link.url,
				link.name,
				social_icon(link.name),
			),
		)
	}
	social_html := strings.join(social_parts[:], "")

	copyright := "<p><small>&copy;</small> 2026</p>"
	if config.author != "" {
		copyright = fmt.aprintf("<p><small>&copy;</small> 2026 %s</p>", config.author)
	}

	return fmt.aprintf(
		`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>%s</title>
  <link rel="stylesheet" href="/css/main.css?v=2">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css">
  <script src="/js/main.js?v=2" defer></script>
</head>
<body>
%s%s<footer>
  <a class="goto-top opacity-0" href="#">%s</a>%s
  <p class="pt-5 prose">Proudly built with <a href="https://odin-lang.org/">Odin</a> and <a href="https://tailwindcss.com/">Tailwindcss</a></p>
%s</footer>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script>hljs.highlightAll();</script>
</body>
</html>
`,
		page_title,
		header,
		body,
		ICON_CHEVRON_UP,
		social_html,
		copyright,
	)
}

social_icon :: proc(name: string) -> string {
	switch strings.to_lower(name) {
	case "github":
		return ICON_GITHUB
	case "rss":
		return ICON_RSS
	}
	return name
}

HEADER :: `
<header>
  <nav>
    <ul>
      <li class="mr-auto"><a href="/">%s</a></li>
      <li><a href="/ideas/">Ideas</a></li>
      <li><a href="/posts/">Posts</a></li>
    </ul>
  </nav>
</header>
`

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
		star = ICON_STAR
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
