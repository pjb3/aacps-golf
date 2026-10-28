require "minitest/autorun"
require "json"
require "yaml"
require "date"
require_relative "../lib/golf"
require_relative "../lib/golf/championship_refresh"

class ChampionshipTest < Minitest::Test
  PARS = Array.new(18, 4).freeze
  CUT = { "share" => 0.4, "teams_min" => 3, "players_min" => 5,
          "final" => true, "boys" => 12, "girls" => 18, "teams" => 40 }.freeze

  def player(name, first:, second:, qualified: true, school: "A")
    { "name" => name, "school" => school, "gender" => "M", "team" => true,
      "qualified" => qualified, "rounds" => [first, second] }
  end

  def test_cumulative_scores_use_par_only_for_played_holes_and_keep_cut_players_last
    ps = [player("Finalist", first: { "1" => 4 }, second: { "1" => 20 }),
          player("Cut", first: { "1" => 5 }, second: {}, qualified: false)]
    board = Golf::Standings.new(ps, pars: PARS, cut: CUT).to_h
    assert_equal %w[Finalist Cut], board["individuals"].map { |p| p["name"] }
    finalist, cut = board["individuals"]
    assert_equal [24, 16, 1, false], finalist.values_at("strokes", "to_par", "thru", "finished")
    assert_equal true, finalist["in_cut"]
    assert_equal false, cut["in_cut"]
    assert_equal "boys", finalist["cut_after"]
    assert_equal 12, board["cut"]["boys"]["rank"]
    assert_equal %w[Out In Out In], finalist["card"].map { |n| n["label"] }
  end

  def test_team_selects_four_separately_each_round_and_freezes_eliminated_teams
    ps = 5.times.map do |i|
      player("A#{i}", first: { "1" => i == 4 ? 10 : 4 }, second: { "1" => i.zero? ? 20 : 4 })
    end
    ps += 4.times.map { |i| player("B#{i}", first: { "1" => 20 }, second: { "1" => 4 }, school: "B") }
    teams = Golf::Standings.new(ps, pars: PARS, cut: CUT).to_h["teams"]
    assert_equal [32, 0], teams.first.values_at("strokes", "to_par")
    assert_equal [80, false], teams.last.values_at("strokes", "in_cut")
    assert_equal 0, teams.last["round_teams"][1]["scored"]
    assert_equal %w[A1 A2 A3 A4], teams.first["round_teams"][1]["players"].select { |p| p["counting"] }.map { |p| p["name"] }
  end

  def test_actual_final_pairings_match_individual_pool_after_team_advancement
    event = YAML.safe_load_file(File.expand_path("../_events/2026-10-26-state-championships.md", __dir__), permitted_classes: [Date])
    # Freeze the evidence used to infer the cut; live score corrections must
    # not change the historical cohort under test.
    first = JSON.parse(File.read(File.expand_path("../sample/golf-genius/2026-qualifiers.json", __dir__)))
    board = Golf::Standings.new(first, pars: event["pars"]).to_h
    teams = board["teams"]
    team_cut = teams[(teams.size * 0.4).floor - 1]["rank"]
    schools = teams.select { |t| t["rank"] <= team_cut }.map { |t| t["school"] }
    first.group_by { |p| p["gender"] }.each do |gender, rows|
      pool = rows.reject { |p| p["team"] && schools.include?(p["school"]) }
      threshold = pool.map { |p| p["total"] }.sort[(pool.size * 0.4).floor - 1]
      assert_equal gender == "M" ? 83 : 89, threshold
      rows.each do |p|
        expected = (p["team"] && schools.include?(p["school"])) || p["total"] <= threshold
        assert_equal expected, p["qualified"], p["name"]
      end
    end
  end
end

class ChampionshipRefreshTest < Minitest::Test
  def test_stop_requires_every_qualifier_but_ignores_eliminated_players
    now = Time.iso8601("2026-10-28T12:00:00-04:00")
    full = (1..18).to_h { |h| [h.to_s, 4] }
    players = [{ "qualified" => true, "rounds" => [full, full] },
               { "qualified" => false, "rounds" => [full, {}] }]
    assert Golf::ChampionshipRefresh.finished?(players, now: now)
    players << { "qualified" => true, "rounds" => [full, { "1" => 4 }] }
    refute Golf::ChampionshipRefresh.finished?(players, now: now)
    refute Golf::ChampionshipRefresh.finished?([], now: now)
  end

  def test_hard_stop_at_four_eastern_even_if_cards_are_incomplete
    players = [{ "qualified" => true, "rounds" => [{}, {}] }]
    refute Golf::ChampionshipRefresh.finished?(players, now: Time.iso8601("2026-10-28T19:59:59Z"))
    assert Golf::ChampionshipRefresh.finished?(players, now: Time.iso8601("2026-10-28T20:00:00Z"))
  end
end
