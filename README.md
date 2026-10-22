# Wiktionary Lookup: dictionary data

Dictionary indexes for [Wiktionary Lookup](https://d33mobile.github.io/wiktionary-lookup-fdroid/),
an offline dictionary app for Android. One gzip-compressed index per language is attached to the
GitHub Releases of this repository, together with `manifest.json` listing them. The app reads

    https://github.com/d33mobile/wiktionary-lookup-data/releases/latest/download/manifest.json

and downloads the languages the user picks.

## manifest.json

```json
{
  "languages": [
    {"code": "de", "name": "German", "entries": 123456, "bytes": 45678901,
     "sha256": "<sha256 of the uncompressed index>", "gzBytes": 12345678,
     "url": "../../download/<tag>/de.idx.gz"}
  ]
}
```

`url` is relative to the manifest URL, so the manifest in the latest release can point at assets
of any release. `bytes` and `sha256` describe the uncompressed index. Since 2026-10-23 every
language also has `details: {url, bytes, sha256, gzBytes, entries}`, the entry pages
(`<code>.details.gz`), an optional second download in the app.

## Uploading

`upload.sh IDX_DIR OUT_DIR TAG` gzips every `IDX_DIR/<code>.idx` (and `<code>.details`) listed in `IDX_DIR/manifest.json`,
rewrites the URLs and uploads everything with `gh release upload`. Releases hold at most
1000 assets, so large sets are split over several tags; the manifest goes into the last one,
which is marked latest.

## Licensing

Dictionary data is derived from English Wiktionary via kaikki.org and is licensed under
CC BY-SA 4.0 (and GFDL). Credit to the Wiktionary contributors and kaikki.org.
