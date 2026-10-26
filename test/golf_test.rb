require "minitest/autorun"
require_relative "../lib/golf"

class GolfTest < Minitest::Test
  PARS = [5, 3, 4, 3, 4, 4, 5, 4, 4, 4, 3, 5, 3, 4, 4, 5, 4, 4].freeze
  COUNTY = File.expand_path("../sample/2026-09-29-county-championship.xlsx", __dir__)
  CHARTWELL = File.expand_path("../sample/2026-09-24-a-division-chartwell.xlsx", __dir__)
  INVITE = File.expand_path("../sample/2026-09-15-40s-invite.xlsx", __dir__)

  def county
    @@county ||= Golf::Standings.new(Golf::Sheet.extract(COUNTY), pars: PARS)
  end

  def chartwell_players
    @@chartwell_players ||= Golf::Sheet.extract(CHARTWELL)
  end

  def chartwell
    @@chartwell ||= Golf::Standings.new(chartwell_players, par: 36)
  end

  def test_county_leaders
    leader = county.individuals.first
    assert_equal ["1", "Davis Balderston", -1], leader.values_at("pos", "name", "to_par")

    team = county.ranked_teams.first
    assert_equal ["1", "Severna Park", 21], team.values_at("pos", "school", "to_par")
  end

  def test_county_counts
    assert_equal 80, county.to_h["player_count"]
    assert county.to_h["cards"]
  end

  # Matches TEAM TOTALS on the sheet's RESULTS tab, except the sheet places
  # Crofton 2nd (it's 3rd; Severna Park's 158 is 2nd).
  def test_chartwell_team_totals
    assert_equal [["1", "Broadneck", 156], ["2", "Severna Park", 158], ["3", "Crofton", 170], ["4", "South River", 172], ["5", "Chesapeake", 176]],
                 chartwell.ranked_teams.map { |t| t.values_at("pos", "school", "strokes") }
    assert_equal 12, chartwell.ranked_teams.first["to_par"]
  end

  def test_chartwell_individuals
    top = chartwell.individuals.first(4).map { |p| p.values_at("pos", "name", "strokes", "to_par") }
    assert_equal [["1", "Ty Swann", 34, -2], ["T2", "Colin Barry", 37, 1], ["T2", "James Jonker", 37, 1], ["4", "Michael Peterson", 38, 2]], top
    refute chartwell.to_h["cards"]
    refute chartwell.to_h["gender_filter"]
  end

  # Campbell Jones and Max Knoepfle are listed apart from Severna Park's team block.
  def test_chartwell_second_block_plays_as_individuals
    individuals = chartwell_players.reject { |p| p["team"] }.map { |p| p["name"] }
    assert_equal ["Campbell Jones", "Max Knoepfle"], individuals
  end

  def test_names_are_cleaned
    names = chartwell_players.map { |p| p["name"] }
    assert_includes names, "Chase Connell"
    assert_includes names, "Charlie Ward"
    assert_includes names, "Nate Fine"
    assert names.none? { |n| n.match?(/\(|\s\s|\A\s|\s\z/) }
  end

  def invite_players
    @@invite_players ||= Golf::Sheet.extract(INVITE)
  end

  # An empty TEAM TOTALS list means individual only.
  def test_invite_is_individual_only
    board = Golf::Standings.new(invite_players).to_h
    refute board["has_teams"]
    assert_empty board["teams"]
    assert board["gender_filter"]
    assert_equal ["1", "Liam Finnegan", 37], board["individuals"].first.values_at("pos", "name", "strokes")
  end

  def test_live_team_match_with_blank_team_totals
    book = RubyXL::Parser.parse(CHARTWELL)
    results = book["RESULTS"]
    header, _, cols = Golf::Sheet.header_rows(results)
    results.each_with_index do |row, r|
      row[cols["Place"] + 1]&.change_contents(nil) if row && r > header
    end
    refute Golf::Standings.new(Golf::Sheet.extract_totals(book), par: 36).to_h["has_teams"]
    players = Golf::Sheet.extract_totals(book, team_event: true)
    board = Golf::Standings.new(players, par: 36).to_h
    assert board["has_teams"]
    assert_equal 5, board["teams"].size
    assert_equal ["Campbell Jones", "Max Knoepfle"], players.reject { |p| p["team"] }.map { |p| p["name"] }
    players.each { |p| p["total"] = nil }
    waiting = Golf::Standings.new(players, par: 36).to_h
    assert waiting["has_teams"]
    assert_empty waiting["teams"]
    assert_equal 5, waiting["short_teams"].size
  end

  def test_invite_dns_and_lost_cards
    board = Golf::Standings.new(invite_players).to_h
    assert_equal [["Devin Crabbe", "DNS"], ["Marick Norton", "DNS"]], board["waiting"].map { |p| p.values_at("name", "status") }
    lost = board["individuals"].select { |p| p["mark"] }.map { |p| p.values_at("name", "strokes") }
    assert_equal [["Evan Lyman", 43], ["Aidan Pelkey", 45], ["Colton Sutherland", 47]], lost
    assert_equal [{ "mark" => "*", "note" => "Lost card" }], board["footnotes"]
  end

  def test_school_names_are_cleaned
    assert_equal "Severna Park", invite_players.find { |p| p["name"] == "Kevin Flanagan" }["school"]
    assert_equal "Broadneck", invite_players.find { |p| p["name"] == "Gavin Monaco" }["school"]
  end

  def test_schedule_sections_and_live
    today = Date.new(2026, 9, 29)
    assert_equal "today", Golf::Schedule.section({ "date" => today }, today)
    assert_equal "upcoming", Golf::Schedule.section({ "date" => Date.new(2026, 9, 30) }, today)
    assert_equal "past", Golf::Schedule.section({ "date" => Date.new(2026, 9, 28) }, today)
    assert_equal "today", Golf::Schedule.section({ "date" => Date.new(2026, 9, 28), "end_date" => Date.new(2026, 9, 30) }, today)

    assert Golf::Schedule.live?({ "date" => today }, today)
    refute Golf::Schedule.live?({ "date" => today, "live" => false }, today)
    refute Golf::Schedule.live?({ "date" => today, "cancelled" => true }, today)
    refute Golf::Schedule.live?({ "date" => Date.new(2026, 9, 28) }, today)

    event = { "date" => Date.new(2026, 10, 6), "live_until" => "2026-10-06T19:00:00-04:00" }
    assert Golf::Schedule.live?(event, event["date"], Time.iso8601("2026-10-06T18:59:59-04:00"))
    assert Golf::Schedule.live?(event, event["date"], Time.iso8601("2026-10-06T19:00:00-04:00"))
    refute Golf::Schedule.live?(event, event["date"], Time.iso8601("2026-10-06T23:00:01Z"))
  end

  def test_school_names
    assert_equal "Chesapeake Science Point", Golf::Schools.canonical("CSP")
    assert_equal "Chesapeake Science Point", Golf::Schools.canonical("Chesapeake Science")
    assert_equal "Severna Park", Golf::Schools.canonical("SP")
    assert_equal "Glen Burnie", Golf::Schools.canonical("Glen Birnie")
    assert_equal "South River", Golf::Schools.canonical("South RIver")
    assert_equal "Chesapeake", Golf::Schools.canonical("Chesapeake")
    assert_equal "Somewhere Else", Golf::Schools.canonical("Somewhere Else")
  end

  def test_corrections_disqualify_a_player
    players = (1..5).map { |i| { "name" => "P#{i}", "school" => "X", "team" => true, "total" => 38 + i } }
    fixed = Golf::Corrections.apply(players, { "P1" => { "status" => "DQ" } })
    board = Golf::Standings.new(fixed, par: 36).to_h
    assert_equal [["P1", "DQ"]], board["waiting"].map { |p| p.values_at("name", "status") }
    assert_equal 40 + 41 + 42 + 43, board["teams"].first["strokes"]
    assert_raises(ArgumentError) { Golf::Corrections.apply(players, { "Nobody" => { "status" => "DQ" } }) }
  end

  def test_ties_share_a_position
    players = [
      { "name" => "A", "school" => "X", "group" => "1A", "scores" => { "1" => 4 } },
      { "name" => "B", "school" => "X", "group" => "1A", "scores" => { "1" => 4 } },
      { "name" => "C", "school" => "X", "group" => "1A", "scores" => { "1" => 6 } },
      { "name" => "D", "school" => "X", "group" => "2A", "scores" => {} }
    ]
    s = Golf::Standings.new(players, pars: PARS)
    assert_equal %w[T1 T1 3], s.individuals.map { |p| p["pos"] }
    assert_equal %w[D], s.waiting.map { |p| p["name"] }
  end

  def test_team_partial_scores_are_ranked
    players = (1..5).map { |i| { "name" => "P#{i}", "school" => "X", "group" => "1", "team" => true, "total" => i < 4 ? 40 : nil } }
    s = Golf::Standings.new(players, par: 36)
    assert_equal [["1", "X", 12, 120]], s.ranked_teams.map { |t| t.values_at("pos", "school", "to_par", "strokes") }
    assert_equal [["X", 3]], s.short_teams.map { |t| t.values_at("school", "scored") }
  end

  def test_team_order_and_minimum_roster_size
    totals = { "Full" => [37, 37, 37, 37, 50], "Partial" => [35, 36, nil, nil],
               "Tie" => [35, nil, nil, nil], "Empty" => [nil, nil, nil, nil],
               "Small" => [30, 31, 32] }
    players = totals.flat_map do |school, scores|
      scores.each_with_index.map { |total, i| { "name" => "#{school} #{i}", "school" => school, "team" => true, "total" => total } }
    end
    board = Golf::Standings.new(players, par: 36).to_h
    assert_equal [["T1", "Partial", -1, 71], ["T1", "Tie", -1, 35], ["3", "Full", 4, 148]],
                 board["teams"].map { |t| t.values_at("pos", "school", "to_par", "strokes") }
    assert_equal ["Empty"], board["unstarted_teams"].map { |t| t["school"] }
    assert_equal 3, board["individuals"].count { |p| p["school"] == "Small" }
    small = Golf::Standings.new(players.select { |p| p["school"] == "Small" }, par: 36).to_h
    refute small["has_teams"]
    assert_empty small["teams"]
    assert_empty small["short_teams"]
  end

  def test_partial_hole_scores_rank_by_par_played
    players = { "Birdie" => { "1" => 4 }, "Par" => { "2" => 3 } }.flat_map do |school, scores|
      (1..4).map { |i| { "name" => "#{school} #{i}", "school" => school, "team" => true, "scores" => i == 1 ? scores : {} } }
    end
    assert_equal [["Birdie", -1], ["Par", 0]],
                 Golf::Standings.new(players, pars: PARS).ranked_teams.map { |t| t.values_at("school", "to_par") }
  end

  def test_totals_without_par_rank_by_strokes
    players = [{ "name" => "A", "school" => "X", "total" => 45 }, { "name" => "B", "school" => "X", "total" => 41 }]
    s = Golf::Standings.new(players)
    assert_equal [["1", "B", nil], ["2", "A", nil]], s.individuals.map { |p| p.values_at("pos", "name", "to_par") }
  end

  CUT = { "share" => 0.4, "teams_min" => 3, "players_min" => 2 }.freeze

  # Ten boys: 40% is 4, and the two tied for 4th both make it.
  def test_cut_takes_top_share_and_ties
    boys = [70, 71, 72, 73, 73, 74, 75, 76, 77, nil].each_with_index.map { |t, i| { "name" => "B#{i}", "school" => "S", "gender" => "M", "total" => t } }
    board = Golf::Standings.new(boys, par: 72, cut: CUT).to_h
    assert_equal({ "rank" => 1, "projected" => 1, "advance" => 4 }, board["cut"]["boys"])
    assert_equal %w[B0 B1 B2 B3 B4], board["individuals"].select { |p| p["in_cut"] }.map { |p| p["name"] }
    assert_equal ["B4"], board["individuals"].select { |p| p["cut_after"] }.map { |p| p["name"] }
  end

  # Separate cuts for boys and girls, each with its own minimum.
  def test_cut_is_per_gender_with_minimum
    players = [["G1", "F", 80], ["B1", "M", 70], ["G2", "F", 81], ["G3", "F", 90], ["B2", "M", 75]]
              .map { |n, g, t| { "name" => n, "school" => "S", "gender" => g, "total" => t } }
    board = Golf::Standings.new(players, par: 72, cut: CUT).to_h
    assert_equal [9, 2], board["cut"]["girls"].values_at("projected", "advance")
    assert_equal [3, 2], board["cut"]["boys"].values_at("projected", "advance")
    assert_equal %w[B1 B2 G1 G2], board["individuals"].select { |p| p["in_cut"] }.map { |p| p["name"] }.sort
    assert_equal %w[B2 G2], board["individuals"].select { |p| p["cut_after"] }.map { |p| p["name"] }.sort
    assert_equal [["B1", "1", "1"], ["B2", "2", "2"], ["G1", "3", "1"], ["G2", "4", "2"], ["G3", "5", "3"]],
                 board["individuals"].map { |p| p.values_at("name", "pos", "gender_pos") }
  end

  # 40% of 4 teams rounds down to 1, but at least 3 advance.
  def test_team_cut_minimum
    players = %w[A B C D].each_with_index.flat_map do |school, i|
      4.times.map { |j| { "name" => "#{school}#{j}", "school" => school, "team" => true, "total" => 72 + i } }
    end
    teams = Golf::Standings.new(players, par: 72, cut: CUT).to_h["teams"]
    assert_equal [true, true, true, false], teams.map { |t| t["in_cut"] }
    assert_equal "C", teams.find { |t| t["cut_after"] }["school"]
  end

  def test_no_cut_by_default
    assert_nil county.to_h["cut"]
    refute county.individuals.first.key?("in_cut")
  end

  # Who's in goes by current position; the projected cut adds the field's
  # average to par on each hole a player has left (B2's last hole averages a
  # double bogey).
  def test_cut_uses_projected_18_hole_scores
    pars = [4, 4]
    players = [
      { "name" => "B1", "school" => "S", "gender" => "M", "scores" => { "1" => 5, "2" => 4 } },
      { "name" => "B2", "school" => "S", "gender" => "M", "scores" => { "1" => 4 } },
      { "name" => "B3", "school" => "S", "gender" => "M", "scores" => { "1" => 6, "2" => 8 } }
    ]
    board = Golf::Standings.new(players, pars: pars, cut: { "share" => 0.4, "teams_min" => 3, "players_min" => 1 }).to_h
    assert_equal %w[B2 B1 B3], board["individuals"].map { |p| p["name"] }
    assert_equal [2, 1, 6], board["individuals"].map { |p| p["projected"] }
    assert_equal({ "rank" => 0, "projected" => 1, "advance" => 1 }, board["cut"]["boys"])
    assert_equal %w[B2], board["individuals"].select { |p| p["in_cut"] }.map { |p| p["name"] }
  end
end
