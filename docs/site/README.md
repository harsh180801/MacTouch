# MacTouch Website

Static public website for MacTouch with install, usage, features, phases, and architecture overview.

## Local preview

From repository root:

```bash
cd docs/site
python3 -m http.server 8080
```

Then open `http://localhost:8080`.

## Deploy options

### GitHub Pages (quick)

1. Push repository.
2. In GitHub repo settings, go to **Pages**.
3. Set source to branch `master` and folder `/docs/site` (or copy files into `docs` if your Pages setup only supports `/docs`).
4. Save and wait for the site URL to appear.

### Netlify / Vercel

- Root publish directory: `docs/site`
- Build command: none (static site)

## Customize

- Main content: `index.html`
- Styling: `styles.css`
