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
| `lib/golf/schedule.rb` | Which events are today / upcoming / past, and which are live. |
| `lib/golf/schools.rb` | Canonical school names ("CSP", "SP", "Glen Birnie" → the real name). |
| `_data/courses.yml` | Front-nine par by course. |
| `_plugins/golf.rb` | Runs the standings at build time and exposes them to templates as `page.board`. |
| `index.html`, `_layouts/event.html` | Homepage and tournament page templates. |

The JSON is the source of truth once an event is over, so hand-fixes (a
misspelled name, say) can go straight into it.

## Adding tournaments

Matches come from the results page
(https://sites.google.com/aacps.org/golf/results). The nightly build runs
`bin/import`, which creates an event file for every match listed there that
doesn't have one yet (lines ending "- Cancelled" become `cancelled: true`), and
`bin/refresh --missing`, which pulls results for past matches. To do it by hand:

```sh
bundle exec bin/import --dry-run   # see what's new
bundle exec bin/import
bundle exec bin/refresh --missing
```

Event files can also be written or edited by hand:

- `title`, `date` (and `end_date` for multi-day events), `course`.
- `sheet_id`, or `results_url` for results hosted elsewhere.
- `par` for the course, if it isn't in `_data/courses.yml` (front-nine pars
  by course name). Hole-by-hole events (like the County Championship) need
  `pars`, a list of every hole's par, for the scorecards.
- `cancelled: true` shows the match struck through and not clickable. Add
  `made_up_on: <date>` if it was replayed later, and `makeup_for: <date>` on
  the replayed match.
- `corrections` fix a player's result without touching the sheet, and survive
  later refreshes, e.g. `Will Robison: { status: DQ }` (no score, not counted)
  or `Jane Doe: { total: 41 }`.
- `live: false` stops refreshing a match on its day (results confirmed final);
  `live: true` keeps refreshing it on other days.
- `live_until: "2026-10-06T19:00:00-04:00"` stops live refreshes after a
  specific time, including its UTC offset.
- `team_event: true` uses ENTRIES rosters when a live match's TEAM TOTALS
  list is still blank, so both individual and team leaderboards appear.

The homepage splits events into Today, Upcoming and Past, opening on Today
when there's a match that day. On a match day, the 15-minute build refreshes
that day's sheets automatically.

The parser understands two sheet layouts, picked automatically:

- **Hole by hole:** group tabs named like `1A`/`6B` with a score per hole.
- **Final scores:** a RESULTS tab with a `Score` column and a TEAM TOTALS list.
  An empty TEAM TOTALS list (the 30's and 40's Invites) means individual only,
  and the page drops its Team view. Scores like `43*` keep their footnote from
  the bottom of the tab (e.g. "Lost card"); entries like `DNS` are shown as-is.

Both need an ENTRIES tab. A school's team is four to six players from its
first block of rows there, ending at a thick bottom border; players below it
or listed separately further down play as individuals. In final-score sheets,
a player missing from ENTRIES (a late substitute) plays for their school. Names are cleaned up on the way in: notes in parentheses are
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
demand ("Run workflow"), every 15 minutes (refreshing today's matches; it
redeploys only if scores changed), and nightly just after midnight Eastern
(importing new matches and rolling the homepage over to the new day). In the repo settings, set **Pages → Source** to
**GitHub Actions**.
