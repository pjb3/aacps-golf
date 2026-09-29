require "minitest/autorun"
require_relative "../lib/golf"

class GolfTest < Minitest::Test
  PARS = [5, 3, 4, 3, 4, 4, 5, 4, 4, 4, 3, 5, 3, 4, 4, 5, 4, 4].freeze
  SAMPLE = File.expand_path("../sample/scores.xlsx", __dir__)

  def standings
    @@standings ||= Golf::Standings.new(Golf::Sheet.extract(SAMPLE), PARS)
  end

  def test_sample_leaders
    leader = standings.individuals.first
    assert_equal ["1", "Davis Balderston", -1], leader.values_at("pos", "name", "to_par")

    team = standings.ranked_teams.first
    assert_equal ["1", "Severna Park", 21], team.values_at("pos", "school", "to_par")
  end

  def test_sample_counts
    assert_equal 80, standings.to_h["player_count"]
  end

  def test_ties_share_a_position
    players = [
      { "name" => "A", "school" => "X", "group" => "1A", "scores" => { "1" => 4 } },
      { "name" => "B", "school" => "X", "group" => "1A", "scores" => { "1" => 4 } },
      { "name" => "C", "school" => "X", "group" => "1A", "scores" => { "1" => 6 } },
      { "name" => "D", "school" => "X", "group" => "2A", "scores" => {} }
    ]
    s = Golf::Standings.new(players, PARS)
    assert_equal %w[T1 T1 3], s.individuals.map { |p| p["pos"] }
    assert_equal %w[D], s.waiting.map { |p| p["name"] }
  end

  def test_team_needs_four_scores
    players = (1..5).map { |i| { "name" => "P#{i}", "school" => "X", "group" => "1A", "team" => true, "scores" => i < 4 ? { "1" => 5 } : {} } }
    s = Golf::Standings.new(players, PARS)
    assert_empty s.ranked_teams
    assert_equal [["X", 3]], s.short_teams.map { |t| t.values_at("school", "scored") }
  end
end
