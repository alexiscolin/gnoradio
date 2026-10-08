# Picking the launch catalog

This pipeline produces the tracks the admin imports with `radio.ImportTrack` (see `docs/SPEC.md` §5).
It only uses the Python 3 standard library; `ffmpeg` is optional (loudness in LUFS).

**Golden rule: everything starts from the allowlist `seeds.json`.** The pipeline never runs an open search.
Quality comes from artists and labels we chose and listened to, not from the archives.

## Steps

```sh
cd tools/curate
python3 curate.py fetch                      # "approved" seeds only
python3 curate.py fetch --include-review     # + "to_review" seeds
python3 curate.py fetch --seed "Komiku"      # a single seed (status ignored)
python3 curate.py loud                       # ebur128 on the first 60 s (HTTP range), flags clipping / loudness, never drops
python3 curate.py hash --max 50              # sha256 (+ LUFS with ffmpeg) of non-Audius files
python3 -m http.server 8077                  # then open http://localhost:8077/review.html
python3 curate.py batch                      # approved.json → import_batch.json
python3 curate.py batch --dry-run            # check every row against the realm rules, write nothing
```

1. **`seeds.json`**: the allowlist. Each seed gives a source (`archive`, `ccmixter`, `audius`), an artist, a collection or a query, a default genre (1 to 20) and a status (archive kind `items` whitelists item identifiers: `ids`, optional `genre_overrides`, `only_licenses`; `exclude_title_re` skips titles):
   - `approved`: listened to, fetch it;
   - `to_review`: check before use (originality, quality);
   - `paused`: ignored.
2. **`fetch`** reads the metadata through the official APIs and filters:
   - **licence**: CC0, CC BY, BY-SA, BY-NC or BY-NC-SA, versions 3.0 and 4.0 only (no ND, no 2.5/2.0/1.0, no jurisdiction ports);
   - **length**: 1:30 to 10:00 (Ambient and Cinematic up to 15:00);
   - **format**: mp3 or ogg;
   - **bitrate**: at least 160 kbps (size×8/length), flagged "low bitrate" under 192; unknown size passes only for VBR MP3 or a stated 192+ kbps format;
   - **for Audius**: no remix, cover, stem or gated track, and a cover image is required.

   The result goes to `candidates.json`, in the `ImportTrack` format.
3. **`hash`** downloads the non-Audius files to compute their sha256. The result is cached in `hashes.json`.
4. **`review.html`**: listen to a clip of each track (from 30% of its length).
   - Keys: `K` keep, `D` drop, `N`/`P` next/previous; `1`–`9`, `0` to fix the genre (1 to 10, with `Shift` 11 to 20).
   - Decisions stay in the browser. **Export approved.json** writes the final file.
5. **`batch`** writes `import_batch.json`: the artists to create first, then the tracks, with the count per genre (target: 80 per station). It blocks tracks without a sha256 and ccMixter tracks without a mirror.

## Devnet seed

`python3 curate.py devseed` is separate from the launch catalog: it writes
`gno/r/gnoradio/devseed/v0/data.gno` (gitignored, local devnet only) from Audius trending lists,
250 tracks per genre by default (`--per`, `--per-artist`, `--batch`).

## Legal rules per source

| Source | What we may do | Obligations |
|---|---|---|
| **archive.org** (artists, netlabels) | play from `https://archive.org/download/…`, copy (CC) | attribution: title, artist, licence with a link, source. Items without `licenseurl` are rejected, even if the title says "(CC-BY)". |
| **ccMixter** (editorial picks) | copy (CC BY) | **mirror required** on IPFS/CDN before import: ccMixter blocks playback from other sites (403). Fill `mirror_audio` in `approved.json`. Full attribution. |
| **Audius** | stream and play in public through the API (Open Music License §1.2, the right granted to "Music Players") | OML §1.5 attribution: artist, ©, OML notice, link to the track. **Cache limited to the session** (API terms §2): never a copy or a fingerprint. No bulk extraction beyond the allowlist. **No AI training** on the tracks. `app_name=GnoRadio` in every call; request a key at api.audius.co/plans before going live. |

Excluded: Free Music Archive (its terms forbid direct links), SoundCloud (radio and aggregation forbidden), Jamendo (commercial licence on request), ND licences. NC is allowed while GnoRadio takes no fee (docs/DEPLOY.md, launch policy).

## Known points

- **Bitrate**: many good archive.org releases are VBR MP3 around 128 to 190 kbps (Scott Buckley at 128). They pass, with a flag.
- **Covers**: ccMixter has none; the realm then draws an SVG cover.
- **Genres**: the seed's genre is the default. For Audius, it comes from the genre the artist declared. It can be fixed while listening.
- **Loudness in LUFS**: needs `ffmpeg` (`brew install ffmpeg`).

## Audius and Jamendo pointers

`pointers.py` builds a batch of pointers (`audius:<id>`, `jamendo:<id>`: genre, duration and
licence only, no title) for `tools/deploy/import.py`. The app reads their titles live; see
docs/DEPLOY.md, "Launch policy".

    python3 tools/curate/pointers.py audius <handle>... [--max 60]
    JAMENDO_CLIENT_ID=… python3 tools/curate/pointers.py jamendo <artist id>... [--max 60]
    python3 tools/curate/pointers.py --selftest
