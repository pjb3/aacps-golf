require "minitest/autorun"
require_relative "../lib/golf"

class GolfGeniusTest < Minitest::Test
  SAMPLE = File.expand_path("../sample/golf-genius", __dir__)
  PARS = [4, 4, 4, 3, 4, 4, 4, 3, 5, 4, 3, 4, 5, 3, 4, 5, 4, 4].freeze

  def sample(name) = File.read(File.join(SAMPLE, name))

  # Golf Genius wraps leaderboard HTML in a JavaScript call.
  def leaderboard(*rows)
    html = rows.map { |id, name, score| "<tr class='aggregate-row' data-aggregate-id='#{id}' data-aggregate-name='#{name} '><td class='score'>#{score}</td></tr>" }.join
    %(window.glg.tournaments2.toggleEvent("1", "<table>#{html.gsub("'", "\\\\'")}<\\/table>", "false");)
  end

  def card(id, scores)
    cells = scores.map { |h, s| "<td class='hole#{h} score'><div class='single-score'><span class='score_box'>\\n#{s}\\n<\\/span><\\/div><\\/td>" }.join
    %(window.glg.tournaments2.toggleDetails("#{id}", "<table><tr class='net-line' data-net-name='x'>#{cells}<\\/tr><\\/table>");)
  end

  def responses
    {
      "/leagues/9/widgets/tournament_results?shared=false&round=5" => <<~HTML,
        <a class="expand-tournament" href="/m">3a/4a Male - Individual - 3a/4a Individual Male</a>
        <a class="expand-tournament" href="/f">3a/4a Female - Individual - 3a/4a Individual Female</a>
        <a class="expand-tournament" href="/t">3a/4a Team - 3a/4a Teams</a>
      HTML
      "/leagues/9/widgets/next_round?shared=false&round=5" => <<~HTML,
        <table class="by_individual_table"><tr class="player_row"><td class="player_name">Ryan Kim <span class="tee_abbr"></span></td><td>9:00 AM</td><td>6B</td><td>Gold - Men</td></tr></table>
      HTML
      "/m" => leaderboard([11, "Ryan Kim", "-3"], [12, "Chase Connell", "+2"], [13, "Ty Swann", "WD"]),
      "/f" => leaderboard([21, "Sy Shafie", "E"]),
      "/t" => leaderboard([31, "Severna Park", "+7"]),
      "/tournaments2/details/11" => sample("details-ryan-kim.js"),
      "/tournaments2/details/12" => card(12, { 1 => 4, 2 => 6 }),
      "/tournaments2/details/13" => card(13, {}),
      "/tournaments2/details/21" => card(21, { 10 => 4 }),
      "/tournaments2/details/31" => sample("details-team-severna-park.js")
    }
  end

  def players
    @players ||= Golf::GolfGenius.extract(league: 9, round: 5, fetch: ->(path) { responses.fetch(path) })
  end

  def player(name) = players.find { |p| p["name"] == name }

  def test_scorecard_from_details_page
    assert_equal({ "6" => 4, "7" => 3, "8" => 3, "9" => 4, "10" => 3, "11" => 3, "12" => 4, "13" => 5 },
                 Golf::GolfGenius.read_card(sample("details-ryan-kim.js")))
  end

  def test_team_roster_from_details_page
    assert_equal ["Chase Connell", "Davis Balderston", "Colin Barry", "Chris Jenkins"],
                 Golf::GolfGenius.read_roster(sample("details-team-severna-park.js"))
  end

  def test_players_from_male_and_female_leaderboards
    assert_equal ["Ryan Kim", "Chase Connell", "Ty Swann", "Sy Shafie"], players.map { |p| p["name"] }
    assert_equal %w[M M M F], players.map { |p| p["gender"] }
    assert_equal "6B", player("Ryan Kim")["group"]
    assert_equal({ "1" => 4, "2" => 6 }, player("Chase Connell")["scores"])
    assert_equal "WD", player("Ty Swann")["status"]
  end

  # Team rosters give schools; Golf Genius's own team scores are ignored.
  def test_team_players_get_their_school
    assert_equal ["Severna Park", true], player("Chase Connell").values_at("school", "team")
    assert_equal [nil, false], player("Ryan Kim").values_at("school", "team")
  end

  def test_team_score_is_worked_out_from_scorecards
    roster = %w[Davis\ Balderston Colin\ Barry Chris\ Jenkins].map { |n| { "name" => n, "school" => "Severna Park", "team" => true, "scores" => { "1" => 4 } } }
    board = Golf::Standings.new(players + roster, pars: PARS).to_h
    team = board["teams"].first
    assert_equal ["Severna Park", 2, 22], team.values_at("school", "to_par", "strokes")
  end
end
