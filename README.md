# AACPS Golf

Leaderboards for Anne Arundel County Public Schools golf, built with Jekyll and
published to GitHub Pages. The homepage lists every tournament, newest first;
each tournament has its own leaderboard page with individual and team standings.

## Setup

Ruby is pinned in `.tool-versions` (mise reads it; so does CI).

```sh
mise install
bundle install
bundle exec jekyll serve --livereload   # http://localhost:4000
bundle exec rake test
```

## How it fits together

| Path | What it is |
| --- | --- |
| `_events/<date>-<name>.md` | One file per tournament: title, date, course, pars, Google Sheet ID, `live` flag. |
| `_data/scores/<same name>.json` | Raw hole-by-hole scores pulled from the sheet (written by `bin/refresh`). |
| `lib/golf/sheet.rb` | Reads the sheet's .xlsx export into player records. |
| `lib/golf/standings.rb` | Scoring rules: to par over completed holes, ties, team best-four. |
| `_plugins/golf.rb` | Runs the standings at build time and exposes them to templates as `page.board`. |
| `index.html`, `_layouts/event.html` | Homepage and tournament page templates. |

The JSON is the source of truth once an event is over, so hand-fixes (a
misspelled name, say) can go straight into it.

## Adding a tournament

1. Create `_events/YYYY-MM-DD-short-name.md` (copy the existing one) with the
   sheet ID, pars and `live: true`. The page URL is `/YYYY/short-name/`.
2. Run `bundle exec bin/refresh` to pull scores, or wait for the scheduled build.
3. After play ends, run a final refresh, set `live: false`, and commit.

The sheet parser expects the same layout as the 2026 County Championship sheet
(group tabs named like `1A`/`6B`, an ENTRIES tab with team dividers). A sheet
laid out differently would need changes in `lib/golf/sheet.rb`.

To load scores from a downloaded file instead of the live sheet:

```sh
bundle exec bin/refresh --file sample/scores.xlsx 2026-09-29-county-championship
```

## Publishing

`.github/workflows/pages.yml` builds and deploys on every push to `main`, on
demand ("Run workflow"), and every 15 minutes. The scheduled run refreshes
events marked `live: true`, commits the new scores, and redeploys only if
something changed. In the repo settings, set **Pages → Source** to
**GitHub Actions**.
