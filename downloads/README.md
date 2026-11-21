# downloads

Published builds live here.

| file | what it is |
| --- | --- |
| `SuperStore.ipa` | always the newest release — this is what both Download buttons serve |
| `SuperStore-<version>.ipa` | a permanent copy of each published version |
| `versions.json` | the list the "Previous versions" section renders |

## Publishing a build

1. Take `SuperStore.ipa` from the newest successful **Verify (simulator)** run —
   the `SuperStore-ipa` artifact. It is built with `-config Release`, so its
   bundle id is `com.superstore.SuperStore` with no team id in it.
2. Put it here twice: as `SuperStore.ipa` and as `SuperStore-<version>.ipa`.
3. Add a row to the top of `versions.json`. Only the newest entry gets
   `"latest": true`; remove it from the one below.
4. Commit and push — Pages picks it up on the next build.

```json
[
  {
    "version": "0.7.0",
    "date": "2026-11-21",
    "config": "Release",
    "size": "32.7 MB",
    "file": "downloads/SuperStore-0.7.0.ipa",
    "latest": true
  }
]
```

## Notes

- Builds are unsigned on purpose. A signed app only installs for the Apple ID
  that signed it, so every user signs their own copy.
- GitHub Pages caps a single file at 100 MB. A build is around 32 MB, so the
  archive has room, but it is not unlimited — old versions can be pruned by
  deleting the file and its row.
