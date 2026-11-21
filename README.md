# website

The SuperStore landing page. It lives on its own branch so it can be served straight
from the branch root (GitHub Pages, or any static host).

```
index.html            the whole page — inline CSS/JS, no build step
assets/icon.png       app icon, copied from branding/ on develop
downloads/            where the shippable IPA goes
.nojekyll             keep Pages from running Jekyll over the files
```

## Publishing a build

The Download buttons point at `downloads/SuperStore.ipa`, which is always the newest
release. Next to it sits a permanent `downloads/SuperStore-v<version>.ipa` for every
version, and `downloads/versions.json` describes them — the page reads that file to show
the current version, the date it was released, and the archive list.

To publish one:

1. Build the app (see `README.md` on `develop`) and bump `MARKETING_VERSION` there.
2. Copy the IPA into `downloads/` as both `SuperStore.ipa` and `SuperStore-v<version>.ipa`.
3. Add a row to the top of `downloads/versions.json` with `"latest": true`.
4. Commit and push this branch — the button starts serving it immediately.

Versions start at `v0.1` and count up. If `SuperStore.ipa` is ever missing, the page
detects it and falls back to linking the CI workflow instead of showing a dead button.

Builds are unsigned on purpose: a signed app is tied to the Apple ID that signed it, so
every user signs their own copy.

## Local preview

Any static server works, from this branch:

```sh
python3 -m http.server 8000
```

Then open <http://localhost:8000>.

## Editing

Everything is in `index.html` — colours live in the `:root` variables at the top,
sections are plain `<section>` blocks. No dependencies, no bundler.
