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

  def test_team_needs_four_scores
    players = (1..5).map { |i| { "name" => "P#{i}", "school" => "X", "group" => "1", "team" => true, "total" => i < 4 ? 40 : nil } }
    s = Golf::Standings.new(players, par: 36)
    assert_empty s.ranked_teams
    assert_equal [["X", 3]], s.short_teams.map { |t| t.values_at("school", "scored") }
  end

  def test_totals_without_par_rank_by_strokes
    players = [{ "name" => "A", "school" => "X", "total" => 45 }, { "name" => "B", "school" => "X", "total" => 41 }]
    s = Golf::Standings.new(players)
    assert_equal [["1", "B", nil], ["2", "A", nil]], s.individuals.map { |p| p.values_at("pos", "name", "to_par") }
  end
end
