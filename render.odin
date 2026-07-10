package main

import "core:fmt"
import "core:os"
import "core:strings"

SITE_TITLE :: "One Idiot Developer"
SITE_DESC :: "This is fine...right?"

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
	for page in pages {
		html := render_page_html(page)
		write_page(output_dir, page.permalink, html)
	}

	home_html := render_home_html(pages)
	write_file(fmt.tprintf("%s/index.html", output_dir), home_html)

	fmt.printfln("Rendered %d pages to %s", len(pages) + 1, output_dir)
}

render_page_html :: proc(page: Page) -> string {
	return fmt.aprintf(
		`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>%s | %s</title>
  <style>%s</style>
</head>
<body>
%s<main>
  <article>
    <h1>%s</h1>
%s    %s
  </article>
</main>
</body>
</html>
`,
		page.title,
		SITE_TITLE,
		CSS,
		NAV,
		page.title,
		render_date(page),
		page.body_html,
	)
}

render_home_html :: proc(pages: []Page) -> string {
	items: [dynamic]string
	defer delete(items)

	for page in pages {
		if page.type != .Post {
			continue
		}
		date_short := page.date
		if len(date_short) > 10 {
			date_short = date_short[:10]
		}
		star := ""
		if page.is_starred {
			star = " \xe2\x98\x85"
		}
		append(
			&items,
			fmt.aprintf(`    <li><a href="%s">%s</a> <time>%s</time>%s</li>`, page.permalink, page.title, date_short, star),
		)
	}

	post_list := strings.join(items[:], "\n")

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
%s<main>
  <header>
    <h1>%s</h1>
    <p>%s</p>
  </header>
  <ul>
%s
  </ul>
</main>
</body>
</html>
`,
		SITE_TITLE,
		CSS,
		NAV,
		SITE_TITLE,
		SITE_DESC,
		post_list,
	)
}

render_date :: proc(page: Page) -> string {
	if page.date == "" {
		return ""
	}
	date_short := page.date
	if len(date_short) > 10 {
		date_short = date_short[:10]
	}
	return fmt.aprintf(`    <time datetime="%s">%s</time>` + "\n", page.date, date_short)
}

write_page :: proc(output_dir: string, permalink: string, html: string) {
	rel := permalink
	if len(rel) > 0 && rel[0] == '/' {
		rel = rel[1:]
	}

	dir := fmt.tprintf("%s/%s", output_dir, rel)
	if err := os.make_directory_all(dir); err != nil {
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
