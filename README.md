# Thor

Thor is a simple Static Site Generator designed for personal blogs and other small websites. 

Its core principals are simplicity and minimal configuration, so you can get started as quickly as possible.

It is based on Hugo, and gingerbill's SSG. Templating is done with (extended?) Mustache  templates. 

## What it does

- Syntax Highlighting server-side (with Tree Sitter)  or client-side with highlight.js
- Mustache Templating
- OpenGraph Tags
- Menus (WIP)
- Extended Markdown ([See below](#extended-markdown))
- Basic (whitespace) minification. 
- Union File System (Modules)

## What it doesn't do
- Internationalization
- Pagination (Yet)
- Themes
- Image Manipulation
- TailwindCSS integration

## Getting Started

Run `thor`
Check out `public/index.html`

Then follow [The Guide]()
For a more complete setup, run `thor new site`. 

## Extended Markdown

- Emoji expansion
- margin style footnotes
- Github style alerts
- [and more]
