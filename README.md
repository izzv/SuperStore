# website

The SuperStore landing page. It lives on its own branch so it can be served
straight from the branch root (GitHub Pages, or any static host).

```
index.html            the whole page — inline CSS/JS, no build step
assets/icon.png       app icon, copied from branding/ on develop
downloads/            where the shippable IPA goes
.nojekyll             keep Pages from running Jekyll over the files
```

## Publishing a build

The Download buttons point at `downloads/SuperStore.ipa`. Nothing is committed
there yet, so the page detects the missing file and falls back to linking the CI
workflow instead of showing a dead button.

To publish one:

1. Build the app (see `README.md` on `develop`).
2. Name the file `SuperStore.ipa` and put it in `downloads/`.
3. Commit and push this branch — the button starts serving it immediately.

Builds are unsigned on purpose: a signed app is tied to the Apple ID that signed
it, so every user signs their own copy.

## Local preview

Any static server works, from this branch:

```sh
python3 -m http.server 8000
```

Then open <http://localhost:8000>.

## Editing

Everything is in `index.html` — colours live in the `:root` variables at the
top, sections are plain `<section>` blocks. No dependencies, no bundler.
