# downloads

Drop the shippable build here as **`SuperStore.ipa`**.

The site links to `downloads/SuperStore.ipa` from the hero and the Download
card. Until that file exists the buttons detect the 404 and point at the CI
workflow instead, so the page never offers a dead link.

Notes:

- Keep the file name exactly `SuperStore.ipa` unless you also update the two
  `href`s in `index.html`.
- GitHub Pages has a 100 MB per-file limit; a sideloadable build is well under
  that.
- Unsigned builds only. A signed `.ipa` is tied to the Apple ID that signed it
  and will not install for anyone else.
