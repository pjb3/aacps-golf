module Golf
  # Hand corrections from an event file, applied on top of the scores pulled
  # from the sheet (so a later refresh can't undo them):
  #
  #   corrections:
  #     Will Robison: { status: DQ }   # no score; shown as DQ, not counted
  #     Jane Doe: { total: 41 }        # fix a mistyped score
  #
  # Keys are player names as shown on the site.
  module Corrections
    module_function

    def apply(players, corrections)
      return players if corrections.nil? || corrections.empty?
      unknown = corrections.keys - players.map { |p| p["name"] }
      raise ArgumentError, "corrections for unknown player(s): #{unknown.join(", ")}" if unknown.any?

      players.map do |p|
        fix = corrections[p["name"]] or next p
        fixed = p.merge(fix.transform_keys(&:to_s))
        fixed.merge!("total" => nil, "scores" => {}) if fix.key?("status") || fix.key?(:status)
        fixed
      end
    end
  end
end
