package main

import "core:fmt"

Ctx :: struct {
	title:      string,
	using page: Page,
	site:       Site,
}

Page :: struct {
	title: string,
}

Site :: struct {
	title: string,
}

main :: proc() {
	site := Ctx {
		site = Site{title = "foo"},
		page = Page{title = "bar"},
	}

	fmt.printfln("%+v", site)
	fmt.printf("%+v", site)
}

