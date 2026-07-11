- [ ] add content-hash fingerprinting for tailwind cache busting.
- [ ] create template language
  - Look at the source for 3 template languages that support mustache syntax,
  and see how they implement the tempaltes, then pick the best one. One of them
  should be Hugo / go.
- [ ] Evaluate Tufte CSS — borrow sidenote CSS or replace TailwindCSS entirely
  - Option B: Steal Tufte's sidenote/margin-note CSS (adapt for dark theme), keep TailwindCSS
  - Option C: Full Tufte CSS — drop TailwindCSS, no build step, semantic HTML, customize for dark theme + Roboto
  - Our sidenote HTML pattern already matches Tufte's exactly
- [ ] Block attributes on code fences (`{ #ex-1 }`) — hello-world.md
- [x] Emoji shortcodes (`:shrug:` etc.) — 2 instances
  - [ ] Backslash in shrug not visible.
- [ ] include-code shortcode (`{{< include-code ... >}}`) — i-ported-fd-to-odin
- [x] Nix build integration — main flake runs thor + tailwindcss instead of Hugo
- [ ] Fix copy-to-clipboard button x-axis positioning inside code blocks
- [ ] Content-hash fingerprinting for CSS and JS cache busting
- [ ] OpenGraph meta tags
