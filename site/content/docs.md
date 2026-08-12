{
  "title": "Docs",
  "date": "2026-07-22T08:54:00-04:00",
  "toc": true
}
<!--
This document serves as the primary reference material for building Thor sites.

It should include reference and description of all

- markdown extensions
- site configuration options
- commandline flags
- frontmatter options
etc.

TODO: Use consistent spacing with mustache tags
-->

## Introduction

This guide assumes you have either read [The Guide](../guide), or have built a [Hugo](https://gohugo.io) site before. It also assumes you have a basic knowledge of HTML and CSS.

## Features

Thor has many features and content processors available. In an effort to provide the best out of the box experience, most of them are enabled by default. Those that aren't are chosen because either: 

1. Significant Performance loses.
2. Unexpected behaviour (content mangling)

If you feel that an extension is in the wrong category, let is know! [^issues]

[^issues]: TODO: Add a link to issues from here.

### Opt-In Features

#### Footnotes

By default, Thor uses Tufte style margin notes instead of footnotes. However, if you prefer Hugo style footnotes, you can enable them in the [config](#configuration) file.

TODO: Explain what tufte style is.

#### Syntax Highlighting

The highlight extension enables server-side syntax highlighting, powered by TreeSitter. This feature requires downloading a grammar file for each language you want to highlight, and will raise your build times from several milliseconds to over 250

#### Minify

If enabled, `minify` will perform simple whitespace removal on all your output `.html` files, and any `.css` files in your `assets` directories. Minifying JavaScript is not supported (yet).

TODO: Do we minify inline css?

#### Sections

The `sections` extension wraps each of your content sections in a `<section>` block. Sections are opened just before each heading, and closed before the next heading, or the end the document, whichever comes first. 

### Opt-Out Features

- emoji
- sidenotes/marginnotes
- syntax highlighting
- heading ids
- Table Of Contents Generation
- [GitHub style alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
- deflist syntax[^deflist]

[^deflist]: This may become opt-in in the future.

## Directories
Like Hugo, a Thor project is a collection of specially named directories, plus an optional config file. All directories are optional, but it is recommended to at least have a `content` directory.

content

: `content` holds your pages and page bundles. If not found, thor will look for content files in the root of your current working directory. See [Content](#content) for more details.

 assets
 : `assets` contains any static files for your site (favicon.ico, etc.), as well as files you want to send through the asset pipeline (CSS or JS files). 
 
layouts

: `layouts` holds your templates and partials. See [Templates](#templates).

 public
 : `public` will contain your completed site.

All of these names can be remapped in `thor.json`.[^remap] 

[^remap]: While directories can be remapped at the site level, [modules](#modules) must (currently) adhere to the defaults.

### Assets

Currently, there is only one asset processor, and that is [the minifier](#minify), though more are planned (i.e. Image processing).

TODO: Expand

## Content
### Pages & Page Bundles

Page content can either be defined in a single file (`contact.md`), or in a directory  (`contact/index.md` + `contact/our-team.jpg`). Single file pages are preferred to page bundles.[^1]

[^1]: That's not you say you shouldn't use bundles, but if you have no additional resources on your page, there's no benefit to using a bundle.

Thor currently supports 2 formats for page files: MarkDown (`.md`),  and HTML (`.html`). 

TODO: Content

### Frontmatter

TODO: Frontmatter

## Menus

TODO: Describe

TODO: Don't forget to highlight differences from Hugo.

## Templates

Sites are built using one or more template files written with an extended version of [mustache](https://mustache.github.io). The [mustache manual](https://mustache.github.io/mustache.5.html) has great explainations and a lot of examples, but this section should tell you everything you need to know. 

TODOS: Gotta describe base templates somewhere. (the same way we describe the partials)

### Tags

The beauty of Mustache is that there is very little syntax; there are just 10 symbols you need learn: `{{`, `{{&`, `{{^`, `{{>`, `{{<`, `{{#`, `/}}`, `{{$`, `{{!`, and `|`.

#### Variables

In order to display a scalar (non-list) value in your template, simply wrap it in double curly braces. e.g. `{{ page.title }}`.

This content will be HTML escaped (for safety), so if the value you're rendering contains HTML, you'll need to use the raw syntax instead `{{& page.title}}`[^raw] which will output the value without escaping your HTML. Do so at your own risk.[^risk] 

[^risk]: Or don't, if you don't know why this is dangerous. 

[^raw]: Mustache also supports raw output through triple brace syntax (`{{{ raw }}}`), but `{{& raw }}` is preferred, as it's easy to accidentily insert too many braces.

Leading and trailing whitespace(s) are ignored by the parser, so the folllowing are all equivilent: `{{& title }}`, `{{&title}}`, `{{&  title}}`, `{{&title }}`.

In most[^most] cases, invalid keys will be silently ignored (nothing between the braces will appear), in keeping with the official mustache spec.

[^most]: TODO: in what cases won't it? spelllcheck + strict mode? Also, people don't care about the spec, they care about how the app works. Also maybe mention strict mode here.


#### Sections
> Sections render blocks of text zero or more times, depending on the value of the key in the current context.

Sections allow you to render text conditionally, and also allow you to render lists[^iffor]. They are opened with `{{#key}}` and closed with `{{/key}}`.

[^iffor]: These would be your `if` and `for` blocks in a logic-ful language.

```mustache
{{og.title}}
Shown if OpenGraph title is set!
{{/og.title}}

<ul>
{{#pages}}
<li>{{name}}</li>
{{/pages}}
</ul>
```

#### Inverted Sections
All of the syntax we've described so far renders text when its value is *not* empty. Inverted sections render text when the value given to them *is* empty.[^unless] This allows you to display special conent when no values exist, for example.

> [!NOTE]
>  Empty values include `""` (an empty string), `[]` (an empty list), `false`

Inverted sections are opened with `{{^key}}` and closed with `{{/key}}`.

```mustache
<ul>
{{#pages}}<li>{{name}}</li>{{/pages}}
</ul>
{{^pages}}
We don't have anything to show you right now, come back later!
{{/pages}}
```

[^unless]: This would be your `if not` or `unless` keyword in a logic-ful template.

#### Partials
Single file templates have limited functionality. Fortunately, mustache lets you break your documents up into multiple files through the use of partials.

To include a partial, you use the `{{>name}}` syntax, where `name` is the path to the partial, relative to the `{{layouts_dir}}/partials` of the module. For example, with the default theme, the `footer` template exists in `{{theme_dir}}/layouts/partials/footer.html`, so you'd include it by adding `{{>footer}}` to you template.

See [Partials](#partials-2) for more information.

<!--
If you want to, your partials can include partials, creating a tree of files. But don't go crazy with it.

> [!WARNING]
> You are limited in the number of partials you can nest, to around 13.
> Please see [context depth](#depth-limit) to learn more.
-->

##### Dynamic Partials

#### Blocks
TODO:

#### Parents
TODO:

Parents can be used by theme developers to create complex templates with multiple content slots.

#### Summary

`{{page.title}}` for normal values
`{{&page.title}}` for values that contain HTML.
`<ul>{{#pages}}<li>{{title}}</li>{{/pages}}</ul>` for list values.
`{{#params.is_starred}}<i class="fas fa-star"></i>{{/params.is_starred}}` for conditional content.
`{{^pages}}No pages yet!{{/pages}}` to draw content when the value is empty.

### Block Names

When building your own templates, you are of course free to pick whatever names you choose for your partials and content slots. However, sticking to conventions helps create consistency in the ecosystem, and reduces friction when relying on built-in templates.

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

When building your page(s), the following keys are accessible to your template files:

`now`

: The Current `DateTime`. see [DateTime](#datetimes)

`date_format`

: The default format to use for dates. Configured in `thor.json:date.format`. 

`timezone`

: The timezone to convert dates to when using `{{ date | format }}`. Configured in `thor.json:date.timezone`. 

`site`

: The site parameters that are usable in templates, see [site](#site).

`pages`

: Returns all regular pages, sorted by `?`. Regular pages exclude index pages like home and section roots.

`posts`
: TODO: Section groupings

`og`

: Contains the [Open Graph](https://ogp.me/) metadata for the current page.

`menus`

: The site's constructed menus. See [menus](#menus).
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

`stylesheets`

:  A list of paths to css files the users wants to include globally. These are rendered by the `{{> styles }}` partial. 

TODO: ^^ Bad sentence? ^^

`scripts`

:  A list of `<script>` tags the users wants to include globally. These are rendered by the `{{> scripts }}` partial. 

#### The Context Stack 
When building your page(s), each template is fed a Context[^ctx] stack that contains all the data you should need to build your page.

[^ctx]: (for developers) `Template_Context` is distinct from Odin's implicit `context` parameter.

The context stack is initialized[^init] as `[site, page, context]`, meaning if you use a key like `{{title}}` in your template, it will first attempt to look up `context.title`, then `page.title`, and finally `site.title`, using the first available value it can find.

[^init]: TODO: Don't use programmer speak.

As you descend into sections/partials, new contexts are placed onto the stack, so they resolve first. (LIFO order). 

```mustache
{{<base}}
{{$main}}
<main>
  {{&page.content}}
  <!-- Is the same as -->
  {{&content}}
  <!-- Or -->
  {{$page}}{{&content}}{{/page}}
  <!-- Or -->
  {{$page.content}}{{&.}}{{/page.content}}
</main>
{{/main}}
{{/base}}
```

##### Depth Limit

For technical reasons, the context depth is limited to 16. This shouldn't matter to most users, but if you're running into errors, please see the [FAQ](./FAQ) for more information.

---
### Filters

Because mustache is a logic-less language, (there are no `for` or `if` keywords), things like grouping, sorting, and filtering, are not possible using standard syntax.

To get around this, Thor extends mustache to include a handful of data filters in the form of pipes. Bash users will feel right at home here.

`group_by <field>`

: Allows you to group pages by the given field. e.g.
```mustache
{{#pages | group_by year }}
<section>
<header>{{$key}} {{! The group's year}}</header>
<ul>
{{#items}}<li>
{{title}} {{! The title of each of that year's pages }}
{{/items}}</li>
</ul>
</section>
{{/pages}}
```

`sort_by <field> [asc|desc]`

: Allows you to sort pages by the given field.

`first [n]`

: Given a list, returns only the first `n` items. `n` defaults to 1. Given a string, returns the first `n` runes of the string. To help catch mistakes, `n` is required for strings. 

`last [n]`

: Given a list, returns only the last `n` items. `n` defaults to 1. Given a string, returns the first `n` runes of the string. To help catch mistakes, `n` is required for strings. 

`format ["format string"]`

: Used to display a date in a particular format. See [DateTimes](#datetimes). If no format is given, the default will be used. 

#### Chaining Pipes

Thor allows you to chain two or more pipes, to allow complex data manipulation. However you are limited to no more than **8 pipes**[^pipes] for any given tag. If you believe you need more than 8 pipes, please [open an issue](../issues) with a **clear** and **concrete** example of the problem you are facing.

[^pipes]: TODO: This number must be kept in-sync with `MAX_PIPES`.

**Examples:**

```mustache
{{ pages | group_by year | first }} {{! All pages from the current year }}
```

```mustache
{{ pages | sort_by date desc | first }} {{! The latest page }}
```


### Partials

Partials are templates that render a portion of a page. To include a partial, the standard [mustache syntax](https://mustache.github.io/mustache.5.html#Partials) is used. All partials are resolved relative to the root partial's directory, so to include a partial at `layouts/partials/my_partial.html`, you would use `{{> my_partial}}`.

Users can create or override as many partials as they want; several are included for convienience:

`{{> title }}`

: The title of the current page. It should be placed inside the `<title>` tag. By default, it will appear as `{{ page.title }} | {{ site.title }}`.

`{{> nav }}`

: Nav renders the main menu for the site (`menus.main`). It should be placed inside the `<body>` tag, just before the `<main>` block.

`{{> home-link }}`

: This partial is rendered inside the home anchor in `{{> nav }}`. By default, it wil display the  name of the site, or `Home` if no name is set.

`{{> styles }}`

: This partial renders any stylesheets specified either by the user (via `params.stylesheets`) or by the theme author (specified directly in the template). `params.stylesheets` is intended as an escape hatch for users that want to add CSS to their site, but don't want to customize any templates. Styles should be placed inside the `<head>` tags.

`{{> scripts }}`

: This partial renders any script tags specified either by the user (via `params.scripts`) or by the theme author (specified directly in the template). `params.scripts` is intended as an escape hatch for users that want to add javascript to their site, but don't want to customize any templates. Scripts should be placed at the end of the `<head>` block.

TODO: Scripts must currently be given in raw form, whereas styles are just paths/urs.

`{{> opengraph }}`

: This partial willl render the Open Graph meta tags for your page. It should be placed inside the `<head>` tag. See the [Open Graph](#open-graph) section for more details.

`{{> footer }}`

: This partial will render content on every page after the main page content. It should be placed at the end of the `<body>` tag. By default, it displays a simple copyright line with the current year and author's name (configured in `params.author.name`).

TODO: `styles`/`css`?

TODO: `comments`?

TODO: `toc`?

TODO: We keep referring to blocks and tags, should probably use consistent language.

### DateTimes

TODO: Should this be a subsection of a "Data Types" section?

Dates are strings in one of the following formats:
<!--
| Format                      | Time zone                    |
| --------------------------- | ---------------------------- |
| `2023-10-15T13:18:50-07:00` | `America/Los_Angeles`        |
| `2023-10-15T13:18:50-0700`  | `America/Los_Angeles`        |
| `2023-10-15T13:18:50Z`      | `Etc/UTC`                    |
| `2023-10-15T13:18:50`       | Default is local system time |
| `2023-10-15`                | Default is local system time |
| `15 Oct 2023`               | Default is local system time |
-->

<table>
<thead>
<tr>
<th>Format</th>
<th>Time zone</th>
</tr>
</thead>
<tbody>
<tr>
<td><code class="inline-code">2023-10-15T13:18:50-07:00</code></td>
<td><code class="inline-code">America/Los_Angeles</code></td>
</tr>
<tr>
<td><code class="inline-code">2023-10-15T13:18:50-0700</code></td>
<td><code class="inline-code">America/Los_Angeles</code></td>
</tr>
<tr>
<td><code class="inline-code">2023-10-15T13:18:50Z</code></td>
<td><code class="inline-code">Etc/UTC</code></td>
</tr>
<tr>
<td><code class="inline-code">2023-10-15T13:18:50</code></td>
<td>Default is&nbsp;local system time</td>
</tr>
<tr>
<td><code class="inline-code">2023-10-15</code></td>
<td>Default is&nbsp;local system time</td>
</tr>
<tr>
<td><code class="inline-code">15 Oct 2023</code></td>
<td>Default is&nbsp;local system time</td>
</tr>
</tbody>
</table>


If you want to display a date in a different format, you can use the `| format` Filter. With no argument, it will default to formatting the date with `site.date_format`.

## Configuration

Thor can be configured through commandline flags, content [frontmatter](#frontmatter), and the configuration file. Settings take precedence in that order, so command line flags will always override configured values.

You can run `thor -help` to list all the available flags.

### Config File

The `thor.json` file at the root of your project is the heart of your Thor site. Hopefully, you'll write your site specific metadata here once, and you'll never have to touch it again.

`title`

: The title of your site. Will be rendered inside the `{{> title}}` partial.

`description`

: A brief description of your site. Can be used by theme authors, or as the default [OpenGraph](#open-graph) description.

`base_url`

: The root URL prepended to all links on your site.

`date.format`

: The default format to display dates in. Write the date you'd like to see formatted as [the go format string]. TODO: Explain

`date.timezone`

: The time zone to localize all formatted dates to. Will attempt to use the local system's zone if left unset. 

TODO: validate the default

TODO: Explain format

`markdown_extensions`

: This setting lets you control which markdown extensions are enabled on your site. It should be a mapping of  extension names to either `true` or `false`.
The following keys are available:
- `emoji`
- `sidenotes`
- `alerts`
- `highlight`
- `sections`
- `headingids`
- `deflists`
- `footnotes`


`content_dir`, `assets_dir`, `output_dir`, `layouts_dir`

: These allow you to change the directory structure of your app. See [Directories](#directories) for more info. 

> [!Note] 
> This will not affect the directory structure of any of your modules.

`modules`

: This setting lets you layer modules onto the Union File System. See [modules](#modules) for more info. 

`params`

: Site-wide user customizable data. See [params](#params) for more info.

`og`

: Site-wide Open Graph metadata. See [Open Graph](#open-graph) for more info.

`menus`

Menu configuration for the site. Note that (unlike Hugo) if your configuration contains this key, frontmatter `menus` will be ignored. See [menus](#menus) for more info. 



## Open Graph

Thor supports [Open Graph](https://ogp.me/) tags, allowing you to customize how your site looks when linked to on social media or in apps like Discord. It is accessible through the `{{>opengraph}}` template, which should be automatically included in your header by your theme.

```html
TODO: {{>opengraph shorcode here}}
```

The options are sourced [using the context stack], first from your page frontmatter, and then from your site config. Thor will attempt to infer as much information as possible, to keep you from needing to set them explictly.

The following keys are available:
- `og.title`
- `og.type`
- `og.image`
- `og.url`
- `og.description`
- `og.locale`
- `og.site_name`
- `og.is_article`*
- `og.published_time`*
- `og.modified_time`*
- `og.section`

Please read [the protocol docs](https://ogp.me/#metadata) for the meaning and use of these keys.

TODO: * keys are not a 1:1 mapping
TODO: Template override support
TODO: how to overwrite defaults (in page frontmatter / thor.json)

## Modules

TODO: Modules

## Themes

TODO: Themes

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
