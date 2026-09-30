require "did_you_mean"

module Golf
  # Canonical AACPS high school names. Sheets abbreviate ("CSP", "SP"),
  # misspell ("Glen Birnie") and mis-case ("South RIver") them, which would
  # otherwise split one school into several or drop it from team totals.
  module Schools
    NAMES = [
      "Annapolis", "Arundel", "Broadneck", "Chesapeake", "Chesapeake Science Point",
      "Crofton", "Glen Burnie", "Meade", "North County", "Northeast", "Old Mill",
      "Severn Run", "Severna Park", "South River", "Southern"
    ].freeze
    ALIASES = { "chesapeake science" => "Chesapeake Science Point" }.freeze

    module_function

    # The canonical name, or the input unchanged if it isn't recognizably a
    # known school.
    def canonical(name)
      key = name.downcase
      NAMES.find { |n| n.downcase == key } ||
        ALIASES[key] ||
        unique(NAMES.select { |n| initials(n) == name }) ||
        unique(NAMES.select { |n| DidYouMean::Levenshtein.distance(n.downcase, key) <= 2 }) ||
        name
    end

    def initials(name) = name.split.map { |w| w[0] }.join

    def unique(matches) = matches.size == 1 ? matches.first : nil
  end
end
