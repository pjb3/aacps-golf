require "rubyXL"
require "rubyXL/convenience_methods"

module Golf
  # Reads the scoring spreadsheet (an .xlsx export of the Google Sheet) into
  # plain player records. No scoring happens here; see Standings for that.
  #
  # - Group tabs (1A, 1B, ... 6B) hold hole-by-hole scores in blocks that each
  #   start with a "Name" header row whose columns C..K give the hole numbers.
  # - The ENTRIES tab gives gender (column D) and team rosters: within each
  #   school's block, players above a medium/thick bottom border on column C
  #   are the team. Schools with no border have no team.
  module Sheet
    GROUP_TAB = /\A\d+[AB]\z/
    SKIP_NAMES = ["Marshal"].freeze
    TEAM_BORDERS = %w[medium thick].freeze

    module_function

    def extract(path)
      book = RubyXL::Parser.parse(path)
      entries = book["ENTRIES"] or raise "#{path}: no ENTRIES tab"
      genders, roster = read_entries(entries)

      players = {}
      book.worksheets.each do |sheet|
        next unless sheet.sheet_name.match?(GROUP_TAB)
        read_group(sheet, players)
      end

      players.values.map do |p|
        p.merge(
          "gender" => genders[p["name"].downcase],
          "team" => roster.include?([p["name"].downcase, p["school"]])
        )
      end
    end

    def norm(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    def read_group(sheet, players)
      holes = nil
      sheet.each do |row|
        next unless row
        first = row[0]&.value
        if first == "Name"
          holes = (2..10).map { |c| v = row[c]&.value; v.is_a?(Numeric) ? v.to_i : nil }
          next
        end
        next unless holes && first && !norm(first).empty? && !SKIP_NAMES.include?(norm(first))

        name = norm(first)
        school = norm(row[1]&.value)
        player = players[[name, school]] ||= { "name" => name, "school" => school, "group" => sheet.sheet_name, "scores" => {} }
        holes.each_with_index do |hole, i|
          v = row[i + 2]&.value
          player["scores"][hole.to_s] = v.to_i if hole && v.is_a?(Numeric) && v > 0
        end
      end
    end

    # Returns [{lowercase name => gender}, Set of [lowercase name, school] on a team].
    def read_entries(sheet)
      genders = {}
      roster = []
      closers = []
      current = nil
      closed = false
      sheet.each_with_index do |row, r|
        next if r < 2 || row.nil?
        name = norm(row[0]&.value)
        school = norm(row[2]&.value)
        genders[name.downcase] = norm(row[3]&.value).then { |g| g.empty? ? nil : g } unless name.empty?
        next if school.empty?

        current, closed = school, false if school != current
        roster << [name.downcase, school] if !name.empty? && !closed
        if TEAM_BORDERS.include?(row[2]&.get_border(:bottom))
          closed = true
          closers << school
        end
      end
      [genders, roster.select { |_, school| closers.include?(school) }.to_set]
    end
  end
end
