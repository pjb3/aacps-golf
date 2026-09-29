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
| `_events/<date>-<name>.md` | One file per tournament: title, date, course, par (`pars` per hole, or `par` for the course), Google Sheet ID, `live` flag. |
| `_data/scores/<same name>.json` | Raw scores pulled from the sheet (written by `bin/refresh`): hole by hole, or one total per player. |
| `lib/golf/sheet.rb` | Reads the sheet's .xlsx export into player records. |
| `lib/golf/standings.rb` | Scoring rules: to par over completed holes, ties, team best-four. |
| `_plugins/golf.rb` | Runs the standings at build time and exposes them to templates as `page.board`. |
| `index.html`, `_layouts/event.html` | Homepage and tournament page templates. |

The JSON is the source of truth once an event is over, so hand-fixes (a
misspelled name, say) can go straight into it.

## Adding a tournament

1. Create `_events/YYYY-MM-DD-short-name.md` (copy an existing one) with the
   title, course, sheet ID and par. The page URL is `/YYYY-MM-DD-short-name/`.
   - Hole-by-hole events (like the County Championship) need `pars`, a list of
     every hole's par, for the scorecards.
   - Final-score events (regular matches) just need the course `par`, e.g.
     `par: 36`. Leave it out to rank by strokes only.
2. For an event in progress, set `live: true` and the scheduled build keeps it
   updated. For a finished event, set `live: false` and pull the scores once:
   `bundle exec bin/refresh YYYY-MM-DD-short-name`.
3. After a live event ends, run a final refresh, set `live: false`, and commit.

The parser understands two sheet layouts, picked automatically:

- **Hole by hole:** group tabs named like `1A`/`6B` with a score per hole.
- **Final scores:** a RESULTS tab with a `Score` column and a TEAM TOTALS list.
  An empty TEAM TOTALS list (the 30's and 40's Invites) means individual only,
  and the page drops its Team view. Scores like `43*` keep their footnote from
  the bottom of the tab (e.g. "Lost card"); entries like `DNS` are shown as-is.

Both need an ENTRIES tab. A school's team is its first block of rows there,
ending at a thick bottom border; players listed separately further down play
as individuals. Names are cleaned up on the way in: notes in parentheses are
dropped, extra spaces removed, and all-lowercase words capitalized (school
names too, e.g. "Severna park").

To load scores from a downloaded file instead of the live sheet:

```sh
bundle exec bin/refresh --file sample/2026-09-29-county-championship.xlsx 2026-09-29-county-championship
```

`jekyll serve` doesn't reload `_plugins` or `lib` when they change; restart it
after editing the Ruby code.

## Publishing

`.github/workflows/pages.yml` builds and deploys on every push to `main`, on
demand ("Run workflow"), and every 15 minutes. The scheduled run refreshes
events marked `live: true`, commits the new scores, and redeploys only if
something changed. In the repo settings, set **Pages → Source** to
**GitHub Actions**.
