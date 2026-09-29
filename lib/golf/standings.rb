module Golf
  # Turns raw player records plus the course pars into ranked individual and
  # team leaderboards, as plain hashes with string keys (ready for Liquid).
  #
  # Scoring rules:
  # - To par counts only the holes a player has completed (shotgun starts mean
  #   raw stroke totals are misleading mid-round).
  # - Team score is the sum of the four best to-par scores among roster players
  #   who have started. Teams with fewer than four scores are left unranked.
  class Standings
    TEAM_COUNTING = 4
    GENDERS = { "M" => "boys", "F" => "girls" }.freeze

    attr_reader :pars

    # pars: array of 18 pars, hole 1 first.
    def initialize(players, pars)
      raise ArgumentError, "need 18 pars, got #{pars.size}" unless pars.size == 18
      @pars = pars
      @players = players.map { |p| score(p) }
    end

    def to_h
      {
        "par" => pars.sum,
        "started_count" => started.size,
        "player_count" => @players.size,
        "individuals" => individuals,
        "waiting" => waiting,
        "teams" => ranked_teams,
        "short_teams" => short_teams
      }
    end

    def individuals
      ranked = stable_sort(started) { |p| [p["to_par"], -p["thru"], p["name"]] }
      with_positions(ranked) { |p| p["to_par"] }.map { |pos, p| p.merge("pos" => pos, "card" => card(p)) }
    end

    def waiting
      @players.reject { |p| started?(p) }
    end

    def ranked_teams
      full = teams.select { |t| t["scored"] >= TEAM_COUNTING }
      ranked = stable_sort(full) { |t| [t["to_par"], t["school"]] }
      with_positions(ranked) { |t| t["to_par"] }.map { |pos, t| t.merge("pos" => pos) }
    end

    def short_teams
      teams.select { |t| t["scored"] < TEAM_COUNTING }.sort_by { |t| t["school"] }
    end

    private

    def score(player)
      scores = player["scores"].to_h { |h, s| [h.to_i, s] }
      strokes = scores.values.sum
      player.merge(
        "scores" => scores,
        "thru" => scores.size,
        "strokes" => strokes,
        "to_par" => strokes - scores.keys.sum { |h| par(h) },
        "gender_key" => GENDERS.fetch(player["gender"], "unk"),
        "start_hole" => player["group"].to_s[/\d+/].to_i
      )
    end

    def par(hole) = pars.fetch(hole - 1)

    def started?(p) = p["thru"] > 0

    def started = @players.select { |p| started?(p) }

    def teams
      @teams ||= @players.select { |p| p["team"] }.group_by { |p| p["school"] }.map do |school, roster|
        scored = stable_sort(roster.select { |p| started?(p) }) { |p| [p["to_par"], -p["thru"]] }
        best = scored.first(TEAM_COUNTING)
        {
          "school" => school,
          "players" => (scored + roster.reject { |p| started?(p) }).each_with_index.map { |p, i| p.merge("counting" => i < TEAM_COUNTING && started?(p)) },
          "scored" => scored.size,
          "to_par" => best.sum { |p| p["to_par"] },
          "strokes" => best.sum { |p| p["strokes"] }
        }
      end
    end

    def card(p)
      [[1..9, "Out"], [10..18, "In"]].map do |range, label|
        played = range.select { |h| p["scores"].key?(h) }
        {
          "label" => label,
          "holes" => range.map { |h| { "hole" => h, "par" => par(h), "score" => p["scores"][h], "mark" => p["scores"][h] && mark(p["scores"][h], par(h)) } },
          "par" => range.sum { |h| par(h) },
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
