require "time"

module Golf
  # Ends today's temporary championship refresh once every finalist has a
  # complete final card, or at the requested Eastern-time deadline.
  module ChampionshipRefresh
    DEADLINE = Time.iso8601("2026-10-28T16:00:00-04:00")
    module_function

    def finished?(players, holes: 18, now: Time.now)
      return true if now >= DEADLINE
      qualifiers = players.select { |p| p["qualified"] == true }
      qualifiers.any? && qualifiers.all? do |p|
        final = p.fetch("rounds", [])[1]
        %w[WD DQ DNS RET].include?(p["status"]) || final && (1..holes).all? { |hole| final[hole.to_s].is_a?(Numeric) && final[hole.to_s].positive? }
      end
    end
  end
end
