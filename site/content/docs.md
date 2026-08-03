{
  "title": "Docs",
  "date": "2026-07-22T08:54:00-04:00"
}

[TOC]

## Introduction

This guide assumes you have either read [The Guide](../guide), or have built a [Hugo](https://gohugo.io) site before. It also assumes you have a basic knowledge of HTML and CSS.

## Features

Thor has many features and content processors available. In an effort to provide the best out of the box experience, most of them are enabled by default. 

### Opt-In Features

TODO: #### deflist syntax

TODO: #### footnotes

#### Minify

If enabled, `minify` will perform simple whitespace removal on all your output `.html` files, and any `.css` files in your `assets` directories. Minifying JavaScript is not supported at this time.

### Opt-Out Features

- emoji
- sidenotes/marginnotes
- syntax highlighting
- heading ids


## Directories
Like Hugo, a Thor project is a collection of specially named directories, plus a config file. 

content

: `content` holds your pages and page bundles.

layouts

: `layouts` holds your templates and partials. 

 assets
 : `assets` contains any static files for your site (favicon.ico, etc.), as well as files you want to send through the asset pipeline (CSS or JS files). 

 public
 : `public` will contain your completed site.

All of these names can be remapped in `thor.json`. 

> [!NOTE] While directories can be remapped at the site level, modules must (currently) adhere to the defaults.

### Asset pipeline

Currently, there is only one asset processor, and that is [the minifier](#minify). 

### Pages & Page Bundles

Page content can either be defined in a single file (`contact.md`), or in a directory  (`contact/index.md`, `contact/our-team.jpg`). Single file pages are preferred to page bundles.[^1]

[^1]: That's not you say you shouldn't use bundles, but if you have no additional resources on your page, there's no benefit to using a bundle. 

Thor currently supports 2 formats for page files: MarkDown (`.md`),  and HTML (`.html`). 

## Templates

### Slots

> [!NOTE] (to self) Template modification is an "advanced" feature, and shoud probably be discussed later in the page. (or possibly in the guide.)

When building your own templates, you are of course free to pick whatever names you  choose for your partials and content slots. However, sticking to conventions helps create consistency in the ecosystem, and prevents friction when relying on a built-in template.

`{{$main}}...{{/main}}`

: the `main` section should be used in templates to denote the part of the page that is unique to that page. For the most part, your templates should look like this

```mustache
{{<base}}
{{$main}}
<main>
  <h1>Actual page content goes here</h1>
  {{&page.content}}
</main>
{{/main}}
{{/base}}

```

### Context

TODO: Context can be a confusing name in Odin.


`now`

: The Current `DateTime`. see [DateTime](#datetimes)

`title`

: The title of the current page. Unless overridden, it will be expand to
  `{{ page.title }} | {{ site.title }}`. [^title]

  [^title]: Is there actually a way to overwrite this?

`date_format`

: The default format to use for dates. Configured in `thor.json:date.format`. 

`timezone`

: The timezone to convert all `| format`ted dates to. Configured in `thor.json:date.timezone`. 

`site`

: The site parameters that are usable in templates, see [site](#site)

`pages`

: Returns all regular pages, sorted by `?`. Regular pages exclude index pages like home and section roots::

`og`

: Contains the [Open Graph](https://ogp.me/) metadata for the current page.

#### Page

`page.content`

: The HTML rendered page content 

TODO: write

#### Site

TODO: Write

#### Params

`site.params` and `page.params` are an escape hatch to let users inject arbetrary data into their website. The following are some conventional examples theme developers  may want to use to ensure a consistent experience across themes.

`author`

: The author of the current page or site. See [schema.org](https://schema.org/author) for the recommended format.

### Filters

`group_by <field>`

: Allows you to group pages by the given field.

`sort_by <field> <asc|desc>`

: Allows you to sort pages by the given field.

`first <n>`

: Given a list, returns only the first `n` items. `n` defaults to 1. Given a string, returns the first `n` runes of the string. To help catch mistakes, `n` is required for strings. 

`last <n>`

: Given a list, returns only the last `n` items. `n` defaults to 1. Given a string, returns the first `n` runes of the string. To help catch mistakes, `n` is required for strings. 

`format "<format string>"`

: Used to display a date in a particular format. See [DateTimes](#datetimes). If no format is given, the default will be used. 

### Partials

Partials are templates that render a portion of a page. To include a partial, the standard [mustache syntax](https://mustache.github.io/mustache.5.html#Partials) is used. All partials are resolved relative to the root partials directory, so to include a partial at `layouts/partials/my_partial.html`, you would use `{{> my_partial}}`.

Users can create as many partials as they want, and several are included for convienience:

`{{> opengraph}}`

: This partial willl render the Open Graph meta tags for your page. It should be placed inside the `<head>` tag. It See the [Open Graph](#open-graph) section for more details.

### DateTimes

Dates are strings in one of the following formats:

| Format                      | Time zone                    |
| --------------------------- | ---------------------------- |
| `2023-10-15T13:18:50-07:00` | `America/Los_Angeles`        |
| `2023-10-15T13:18:50-0700`  | `America/Los_Angeles`        |
| `2023-10-15T13:18:50Z`      | `Etc/UTC`                    |
| `2023-10-15T13:18:50`       | Default is local system time |
| `2023-10-15`                | Default is local system time |
| `15 Oct 2023`               | Default is local system time |

If you want to display a date in a different format, you can use the `| format` Filter. With no argument, it will default to formatting the date with `site.date_format`.

## Menus

TODO: Describe

## Open Graph

TODO: default Template support
TODO: Template override support
TODO: how to overwrite defaults (in page frontmatter / thor.json)

## Zen

> The guding principals behind Thor.

Simpler is Better

: We are [Grug](https://grugbrain.dev/) developers. We do everything the "dumb" way first, then optimize the **measured** bottlenecks.

Zero is Beautiful

: The less configuration needed, the better. A site can be built from multiple modules or a single `index.md`.

On By Default

: Users shouldn't have to enable features, unless those features significantly impact performance or mangle regular content.

Fault Tolerant

: When possible, mistakes should be recovered with warnings. When fatal errors occur, the user should have all the information they need to fix it quickly.
