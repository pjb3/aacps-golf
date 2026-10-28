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
| `lib/golf/golf_genius.rb` | Reads a Golf Genius round (the State Championship) into the same player records. |
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
- `golf_genius: { league: ..., round: ... }` instead of `sheet_id` pulls a
  Golf Genius round (ids from its results widget URL,
  `/leagues/<league>/widgets/tournament_results?round=<round>`). Players and
  hole-by-hole scores come from the Male and Female leaderboards, team rosters
  from the Team leaderboard; team scores are worked out here, since Golf
  Genius's are wrong. Golf Genius gives no school for individual qualifiers,
  so `bin/refresh` uses the school each name has in our other events, if any;
  set others with `corrections`, e.g. `Marco Saba: { school: Wootton }`.
- For a two-round championship, add `final_round` and `classification` (e.g.
  `"3a/4a"`) under `golf_genius`. The importer keeps chronological `rounds`
  scorecards and uses the finals tee sheet to identify qualifiers. Individual
  totals combine rounds; team totals choose the counting four separately each
  round. Eliminated teams keep only their first-round result.
- A completed first-round cut uses `cut: { share: 0.4, teams_min: 3,
  players_min: 5, final: true, boys: 12, girls: 18, teams: 37 }`; thresholds
  are scores to par and stay fixed during finals. For 2026 3A/4A, the observed
  qualifiers match this inferred formula: advance the top 40% of teams first
  (six of 17, with ties), then take 40% of the remaining players separately
  by gender, rounded down, with ties. Removing advancing team members leaves
  54 boys (21st score: 83) and 34 girls (13th score: 89). This matches all 112
  players' inclusion/exclusion in the [finals pairings](https://www.golfgenius.com/pages/13173425444726285106).
  This is an inference from the published results, not confirmation from the
  tournament committee. The old projection counted the entire individual field.
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
demand ("Run workflow"), and nightly at 5:05 UTC (12:05 a.m. EST / 1:05 a.m.
EDT), importing new matches and rolling the homepage over to the new day. In
the repo settings, set **Pages → Source** to **GitHub Actions**.

### Cloud scheduler monitor

`cloudflare-monitor/` contains the Cloudflare Worker source for an independent
GitHub Actions trigger. Its Cron Trigger and `GITHUB_TOKEN` secret are currently
removed. To reactivate it, restore the `*/10 * * * *` Cron Trigger and configure
a fine-grained GitHub token with Actions read and write access for
`pjb3/aacps-golf` as the `GITHUB_TOKEN` secret.

### October 28 championship refresh

GitHub Actions checks scores at the top of each hour from 9 a.m. through
4 p.m. Eastern on October 28, 2026; the 4 p.m. run finalizes live status.
Scheduling is best effort and may be delayed or dropped by GitHub, especially
at the top of the hour. The earlier ten-minute schedule produced no observed
runs and was replaced with this hourly schedule.
`bin/finish-championship` sets `live: false` once every qualified player has
18 final-round scores or at 4 p.m., whichever comes first. `live_until` also
prevents fetching after the deadline. The temporary schedules are gated to
October 28, 2026 and skip builds after completion; the nightly schedule is
unchanged. This runs on GitHub and does not depend on a local computer or a
ChatGPT session. The October 28 cron entry can be removed afterward.
