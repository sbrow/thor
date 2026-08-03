{
  "title": "Guide",
  "date": "2026-07-12T08:55:00-04:00"
}
[TOC] 

Thank you for choosing thor for your site building needs. This guide attempts to make it as easy as possible to get started.

> [!NOTE]: This guide assumes you have a basic knowledge of using command line interfaces, file systems, and text editors. 


Start by creating a new directory called `my-site`. This will be the home of your first Thor site. 

If you haven't already, running `thor` in your new directory should create this guide in `./public/index.html`.

At the heart of any good SSG is the content files. Thor supports markdown (`.md`) and `.html` files.

Let's make a home page - copy the following text and place it into `./index.md`

```md
# Hello, World! 

Welcome to your new site. 
```

Run `thor` again, and you should see new content in `public/index.html`.


