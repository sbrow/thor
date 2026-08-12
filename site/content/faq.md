{
  "title": "FAQ",
  "date": "2026-08-30T10:17:00-04:00",
  "toc": true
}
<!--
TODO: Make sure issue link is legit
-->
## context stack depth exceeded  (possible recursive section/partial)

To maintain high performance and encourage maintainable sites, the context stack can never be more than 16 items deep. What does this mean?

Every time you enter a section or a partial, the closest referenced item gets pushed onto the stack. if you then enter another partial, or reference a nested object inside of that, you'll add another item.

This is easier to see with examples:

```mustache
{{! base.html }}
<html>
<head>
  <title>
    {{ title }}
	{{! stack size = 3 throughout the file }}
  </title>
</head>
<body>
  {{> now}}
  <nav>
    <ul>
	{{#pages}}
	  <li>{{name}} {{! stack size = 4 within #pages}}</li>
	{{/pages}}
    </ul>
  </nav>

{{> footer}}
</body>
</html>
```

```mustache
{{! partials/footer.html }}

{{! stack size = 4 throughout the file (when called from base.html) }}
<footer>
{{#params}}
  <p>&copy; {{author.name}} {{> now}}</p>
  {{! stack size = 5 inside #params }}
{{/params}}
{{/site}}
</footer>
```

```mustache
{{! partials/now.html }}

{{! stack size =
    4 when called from base.html
	6 when called from #params inside of footer.html
}}

{{ now | format }}
```

The stack size starts at 3 because the stack is preloaded with `[site, page, context]`, allowing you to reference values like `title` or `params` from `page` or `site` without having to use the fully qualified name `{{site.title}}`.

> [!NOTE]
> If your sites needs a context depth higher than 16, please reach out and open an issue[^issue] with a **clear** and **concrete** example of what you're trying to do.
