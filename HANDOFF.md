# Handoff: live high school golf leaderboard → static site on GitHub Pages

## What this is
A live leaderboard for the AACPS County Championship (9/29, Compass Pointe South/West, par 72).
Scores are entered during play into a public Google Sheet:
https://docs.google.com/spreadsheets/d/1QQqY90W8G-0_pdWNXGJBRMfainZy5SfUrBkRa-3YgvQ

`generate.py` reads an .xlsx export of that sheet and writes a single self-contained
`dist/index.html` (individual + team leaderboards). It works today:

    pip install openpyxl
    python generate.py sample/scores.xlsx dist

`sample/scores.xlsx` is a snapshot from 1:12 PM ET for testing.

## Goal
Publish the page to GitHub Pages and refresh it automatically about every 15 minutes during play.

## Suggested approach
Jekyll isn't needed, because the generator already produces finished HTML.
1. A GitHub Actions workflow on `schedule` (cron `*/15 * * * *`) plus `workflow_dispatch` for manual refreshes.
2. The workflow downloads the sheet as xlsx. The sheet is shared publicly, so
   `https://docs.google.com/spreadsheets/d/<ID>/export?format=xlsx` should work without auth.
   Verify this first.
3. Run `generate.py`, then deploy `dist/` with `actions/upload-pages-artifact` + `actions/deploy-pages`.
4. Put the sheet ID in a repo variable so the same setup can be reused for other events.

GitHub's scheduled runs can be delayed by several minutes and only run on the default branch.
Manual dispatch is the fallback when a refresh is needed right away.

## Scoring rules implemented (keep these)
- **To par:** calculated only over holes each player has actually completed. Players start on
  different holes (shotgun: 1A, 1B, 18A … 6B), so raw stroke totals are misleading mid-round.
  The sheet's own RESULTS tab ranks by raw strokes; don't use it.
- **Pars:** 5 3 4 3 4 4 5 4 4 / 4 3 5 3 4 4 5 4 4 (hardcoded in `PAR`).
- **Group tabs** (names match `^\d+[AB]$`) hold hole-by-hole scores in two blocks, each with a
  "Name" header row whose hole numbers come from row labels. Holes not yet played are empty.
- **Team rosters** come from the ENTRIES tab. Within each school's block, players above the
  medium/thick bottom border on column C are the team (up to 6). Anyone below the border plays
  as an individual only. Schools with no border (Chesapeake Science, Glen Burnie, Northeast,
  Old Mill) have no team.
- **Team score:** the sum of the 4 best to-par scores among roster players who have started.
  Teams with fewer than 4 scores are left unranked. The page lists all roster players and marks
  the counting four.
- **Gender** (Boys/Girls filter) comes from ENTRIES column D. Players with no value appear under All only.
- **Known data quirks:** trailing spaces in names (normalized). Colt Jett (Annapolis) is on ENTRIES
  but in no group. "Bryn Calicoat" on ENTRIES appears as "Bryan Calicoat" on tab 9B. Group 15A
  hadn't posted scores in the snapshot.

## UI behavior to preserve
- Individual/Team toggle. Boys/All/Girls filter on the individual view.
- Clicking or tapping a player row (also Enter/Space) toggles an inline scorecard. The only hover
  affordance is the pointer cursor and a row tint; there is no caret, and row height must not change.
- Scorecard marks: circle = birdie, double circle = eagle, square = bogey,
  double square = double bogey or worse, dot = not yet played.
- Light/dark theme and mobile safe-area padding are already handled in `template.html`.

## Cleanup worth doing
- `generate.py` was consolidated from chat prototypes. Tidy it into functions, and add a small
  test using `sample/scores.xlsx`. With STAMP="1:12 PM ET, Sep 29" the known-good output leaders are
  Davis Balderston −1 and Severna Park +21.
- The timestamp uses a fixed UTC−4 offset; switch to `zoneinfo("America/New_York")`.
- Optionally add a client-side note like "updated N min ago", computed from an embedded ISO timestamp.
