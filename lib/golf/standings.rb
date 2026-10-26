module Golf
  # Turns raw player records into ranked individual and team leaderboards, as
  # plain hashes with string keys (ready for Liquid).
  #
  # Players come in one of two shapes (see Sheet):
  # - hole by hole: "scores" => {hole => strokes}; needs the per-hole pars.
  # - totals: "total" => strokes, or nil if no score was posted; optionally
  #   "status" (e.g. "DNS") when there's no score, or "mark" and "note" for a
  #   footnoted score (e.g. "*" and "Lost card").
  #
  # Scoring rules:
  # - To par counts only the holes a player has completed (shotgun starts mean
  #   raw stroke totals are misleading mid-round). Without a par, players are
  #   ranked by strokes.
  # - Team score is the sum of the four best scores among roster players who
  #   have posted one. Partial totals are ranked during play; rosters with
  #   fewer than four tournament players are excluded from team standings.
  # - With a cut (the State Championship semifinals, see the MPSSAA golf
  #   bulletin), the top `share` of teams, and of boys and girls separately,
  #   make it, rounded down but at least `teams_min` / `players_min`; ties at
  #   the cutoff are in. Who's inside the line goes by current position. The
  #   projected cut is the score it will take after 18 holes: the same place
  #   in the order of projected scores, each player's score so far plus the
  #   field's average to par (same gender, since boys and girls play
  #   different tees) on each hole they have left, rounded to a whole stroke.
  #   A team's projection is the sum of its best four. Once everyone
  #   finishes, projections are the final scores.
  class Standings
    TEAM_COUNTING = 4
    GENDERS = { "M" => "boys", "F" => "girls" }.freeze
    CUT_GROUPS = %w[teams boys girls].freeze

    attr_reader :pars, :par

    # pars: per-hole pars, hole 1 first (needed for hole-by-hole scores).
    # par: course par, for totals-only events; defaults to the sum of pars.
    # cut: {"share" => 0.4, "teams_min" => 3, "players_min" => 5}, or nil.
    def initialize(players, pars: nil, par: nil, cut: nil)
      @pars = pars
      @par = par || pars&.sum
      @cut = cut
      @players = players.map { |p| score(p) }
      raise ArgumentError, "hole-by-hole scores need per-hole pars" if cards? && !pars
    end

    def to_h
      {
        "par" => par,
        "to_par" => !par.nil?,
        "cards" => cards?,
        "gender_filter" => (@players.map { |p| p["gender_key"] } & %w[boys girls]).size == 2,
        "has_teams" => teams.any?,
        "footnotes" => @players.filter_map { |p| { "mark" => p["mark"], "note" => p["note"] } if p["mark"] }.uniq,
        "started_count" => started.size,
        "player_count" => @players.size,
        "individuals" => individuals,
        "waiting" => waiting,
        "teams" => ranked_teams,
        "unstarted_teams" => teams.select { |t| t["scored"].zero? }.sort_by { |t| t["school"] },
        "short_teams" => short_teams,
        "cut" => cut_lines
      }
    end

    # With a cut, each player's "in_cut", and "cut_after" (gender key) on the
    # last player in for their gender, where the page draws the cut line.
    def individuals
      @individuals ||= begin
        ranked = stable_sort(started) { |p| [p["rank"], -p["thru"], p["name"]] }
        rows = with_positions(ranked) { |p| p["rank"] }.map do |pos, p|
          p.merge("pos" => pos, "card" => cards? ? card(p) : nil, "projected" => projected(p))
        end
        mark_cut(rows) { |p| p["gender_key"] }
      end
    end

    def waiting
      @players.reject { |p| started?(p) }
    end

    def ranked_teams
      @ranked_teams ||= begin
        scored = teams.select { |t| t["scored"].positive? }
        ranked = stable_sort(scored) { |t| [t["rank"], t["school"]] }
        rows = with_positions(ranked) { |t| t["rank"] }.map { |pos, t| t.merge("pos" => pos) }
        mark_cut(rows) { "teams" }
      end
    end

    # {"teams" / "boys" / "girls" => {"rank" => current cut score,
    # "projected" => projected 18-hole cut score, "advance" => how many make
    # it}}, for those with anyone ranked; nil without a cut.
    def cut_lines
      return unless @cut
      ranked = { "teams" => ranked_teams }.merge(individuals.group_by { |p| p["gender_key"] }.slice("boys", "girls"))
      ranked.filter_map do |group, rows|
        line = cut_line(group, rows) or next
        [group, line]
      end.to_h
    end

    def short_teams
      teams.select { |t| t["scored"] < TEAM_COUNTING }.sort_by { |t| t["school"] }
    end

    private

    # How many make the cut in a group, from the whole field (players yet to
    # post a score count toward its size).
    def cut_size(group)
      field = group == "teams" ? teams.size : @players.count { |p| p["gender_key"] == group }
      min = @cut.fetch(group == "teams" ? "teams_min" : "players_min")
      [(field * @cut.fetch("share")).floor, min].max
    end

    def cut_line(group, rows)
      return if rows.empty?
      advance = cut_size(group)
      at = [advance, rows.size].min - 1
      { "rank" => rows.map { |r| r["rank"] }.sort[at], "projected" => rows.map { |r| r["projected"] }.sort[at], "advance" => advance }
    end

    # Projected final score (to par, or strokes without a par), as a whole
    # number. See the class comment.
    def projected(p)
      return p["rank"] unless pars && !p["finished"]
      left = (1..pars.size).reject { |h| p["scores"].key?(h) }
      (p["to_par"] + left.sum { |h| hole_average(p["gender_key"], h) }).round
    end

    # The field's average score to par on a hole, among players of the given
    # gender key who have played it (else anyone who has; else par).
    def hole_average(gender_key, hole)
      @hole_averages ||= Hash.new do |memo, (g, h)|
        played = ->(ps) { ps.filter_map { |q| q["scores"][h] } }
        strokes = played.call(@players.select { |q| q["gender_key"] == g })
        strokes = played.call(@players) if strokes.empty?
        memo[[g, h]] = strokes.empty? ? 0.0 : strokes.sum.fdiv(strokes.size) - hole_par(h)
      end
      @hole_averages[[gender_key, hole]]
    end

    def mark_cut(rows, &group_of)
      return rows unless @cut
      # Players with no gender listed have no cut.
      lines = rows.group_by(&group_of).slice(*CUT_GROUPS).to_h { |group, grows| [group, cut_line(group, grows)] }
      in_cut = ->(r) { (line = lines[group_of.call(r)]) && r["rank"] <= line["rank"] }
      last_in = rows.each_with_index.select { |r, _| in_cut.call(r) }
                    .group_by { |r, _| group_of.call(r) }.transform_values { |rs| rs.last[1] }
      rows.each_with_index.map do |r, i|
        group = group_of.call(r)
        next r unless lines.key?(group)
        r.merge("in_cut" => in_cut.call(r), "cut_after" => last_in[group] == i ? group : nil)
      end
    end

    def cards?
      @cards ||= @players.any? { |p| p["scores"]&.any? }
    end

    def score(player)
      scores = player.fetch("scores", {}).to_h { |h, s| [h.to_i, s] }
      total = player["total"]
      started = !total.nil? || !scores.empty?
      strokes = total || scores.values.sum
      par_played = total ? par : (pars && scores.keys.sum { |h| hole_par(h) })
      to_par = started && par_played ? strokes - par_played : nil
      player.merge(
        "scores" => scores,
        "strokes" => strokes,
        "thru" => scores.size,
        "finished" => !total.nil? || (!pars.nil? && scores.size == pars.size),
        "started" => started,
        "to_par" => to_par,
        "rank" => to_par || strokes,
        "gender_key" => GENDERS.fetch(player["gender"], "unk"),
        "start_hole" => player["group"].to_s[/\d+/].to_i
      )
    end

    def hole_par(hole) = pars.fetch(hole - 1)

    def started?(p) = p["started"]

    def started = @players.select { |p| started?(p) }

    def teams
      @teams ||= @players.select { |p| p["team"] }.group_by { |p| p["school"] }.filter_map do |school, roster|
        next if roster.size < TEAM_COUNTING
        scored = stable_sort(roster.select { |p| started?(p) }) { |p| [p["rank"], -p["thru"]] }
        best = scored.first(TEAM_COUNTING)
        to_par = par && best.sum { |p| p["to_par"] }
        strokes = best.sum { |p| p["strokes"] }
        {
          "school" => school,
          "players" => (scored + roster.reject { |p| started?(p) }).each_with_index.map { |p, i| p.merge("counting" => i < TEAM_COUNTING && started?(p)) },
          "scored" => scored.size,
          "to_par" => to_par,
          "strokes" => strokes,
          "rank" => to_par || strokes,
          "projected" => scored.map { |p| projected(p) }.sort.first(TEAM_COUNTING).sum
        }
      end
    end

    def card(p)
      nines = pars.each_slice(9).with_index.map { |nine, i| (i * 9 + 1)..(i * 9 + nine.size) }
      labels = nines.size == 1 ? ["Total"] : %w[Out In]
      nines.zip(labels).map do |range, label|
        played = range.select { |h| p["scores"].key?(h) }
        {
          "label" => label,
          "holes" => range.map { |h| { "hole" => h, "par" => hole_par(h), "score" => p["scores"][h], "mark" => p["scores"][h] && mark(p["scores"][h], hole_par(h)) } },
          "par" => range.sum { |h| hole_par(h) },
          "total" => played.empty? ? nil : played.sum { |h| p["scores"][h] }
        }
      end
    end

    def mark(strokes, par)
      case strokes - par
      when ..-2 then "eagle"
      when -1 then "birdie"
      when 0 then "par"
      when 1 then "bogey"
      else "dbl"
      end
    end

    # Ruby's sort_by isn't stable; ties keep their original order.
    def stable_sort(items, &key)
      items.each_with_index.sort_by { |item, i| [*key.call(item), i] }.map(&:first)
    end

    # [[pos label, item], ...] where tied keys share a position, e.g. "T3".
    def with_positions(items, &key)
      positions = []
      items.each_with_index do |item, i|
        positions << (i.positive? && key.call(item) == key.call(items[i - 1]) ? positions.last : i + 1)
      end
      counts = positions.tally
      positions.zip(items).map { |pos, item| ["#{"T" if counts[pos] > 1}#{pos}", item] }
    end
  end
end
