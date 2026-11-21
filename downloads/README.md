# downloads

Published builds live here.

| file | what it is |
| --- | --- |
| `SuperStore.ipa` | always the newest release — this is what both Download buttons serve |
| `SuperStore-v<version>.ipa` | a permanent copy of each published version |
| `versions.json` | the list the page reads: newest version, its release date, the archive |

Version labels start at `v0.1` and count up — `v0.2`, `v0.3`, and so on. The label is
the app's `CFBundleShortVersionString` with a `v` in front, so bumping `MARKETING_VERSION`
in `Build.xcconfig` on `develop` is what changes it.

## Publishing a build

1. Take `SuperStore.ipa` from the newest successful **Verify (simulator)** run — the
   `SuperStore-ipa` artifact. It is built with `-config Release`, so its bundle id is
   `com.superstore.SuperStore` with no team id in it.
2. Put it here twice: as `SuperStore.ipa` and as `SuperStore-v<version>.ipa`.
3. Add a row to the top of `versions.json`. Only the newest entry gets `"latest": true`;
   remove it from the one below. `date` is the day the build was published, as
   `YYYY-MM-DD`.
4. Commit and push — Pages picks it up on the next build, and the page shows the version
   and date straight from that first row.

```json
[
  {
    "version": "v0.1",
    "date": "2026-11-21",
    "config": "Release",
    "size": "25.3 MB",
    "file": "downloads/SuperStore-v0.1.ipa",
    "latest": true
  }
]
```

## Notes

- Builds are unsigned on purpose. A signed app only installs for the Apple ID that
  signed it, so every user signs their own copy.
- GitHub Pages caps a single file at 100 MB. A build is around 25 MB, so the archive has
  room, but it is not unlimited — old versions can be pruned by deleting the file and
  its row.
