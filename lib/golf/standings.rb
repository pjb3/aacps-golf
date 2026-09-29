module Golf
  # Turns raw player records into ranked individual and team leaderboards, as
  # plain hashes with string keys (ready for Liquid).
  #
  # Players come in one of two shapes (see Sheet):
  # - hole by hole: "scores" => {hole => strokes}; needs the per-hole pars.
  # - totals: "total" => strokes, or nil if no score was posted.
  #
  # Scoring rules:
  # - To par counts only the holes a player has completed (shotgun starts mean
  #   raw stroke totals are misleading mid-round). Without a par, players are
  #   ranked by strokes.
  # - Team score is the sum of the four best scores among roster players who
  #   have posted one. Teams with fewer than four scores are left unranked.
  class Standings
    TEAM_COUNTING = 4
    GENDERS = { "M" => "boys", "F" => "girls" }.freeze

    attr_reader :pars, :par

    # pars: per-hole pars, hole 1 first (needed for hole-by-hole scores).
    # par: course par, for totals-only events; defaults to the sum of pars.
    def initialize(players, pars: nil, par: nil)
      @pars = pars
      @par = par || pars&.sum
      @players = players.map { |p| score(p) }
      raise ArgumentError, "hole-by-hole scores need per-hole pars" if cards? && !pars
    end

    def to_h
      {
        "par" => par,
        "to_par" => !par.nil?,
        "cards" => cards?,
        "gender_filter" => (@players.map { |p| p["gender_key"] } & %w[boys girls]).size == 2,
        "started_count" => started.size,
        "player_count" => @players.size,
        "individuals" => individuals,
        "waiting" => waiting,
        "teams" => ranked_teams,
        "short_teams" => short_teams
      }
    end

    def individuals
      ranked = stable_sort(started) { |p| [p["rank"], -p["thru"], p["name"]] }
      with_positions(ranked) { |p| p["rank"] }.map do |pos, p|
        p.merge("pos" => pos, "card" => cards? ? card(p) : nil)
      end
    end

    def waiting
      @players.reject { |p| started?(p) }
    end

    def ranked_teams
      full = teams.select { |t| t["scored"] >= TEAM_COUNTING }
      ranked = stable_sort(full) { |t| [t["rank"], t["school"]] }
      with_positions(ranked) { |t| t["rank"] }.map { |pos, t| t.merge("pos" => pos) }
    end

    def short_teams
      teams.select { |t| t["scored"] < TEAM_COUNTING }.sort_by { |t| t["school"] }
    end

    private

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
      @teams ||= @players.select { |p| p["team"] }.group_by { |p| p["school"] }.map do |school, roster|
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
          "rank" => to_par || strokes
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
