require "rubyXL"
require "rubyXL/convenience_methods"
require "set"

module Golf
  # Reads a scoring spreadsheet (an .xlsx export of the Google Sheet) into
  # plain player records. No scoring happens here; see Standings for that.
  #
  # Two layouts are supported:
  #
  # - Hole by hole (County Championship): group tabs (1A, 1B, ... 6B) hold
  #   scores in blocks that each start with a "Name" header row whose columns
  #   C..K give the hole numbers. Players get "scores" => {hole => strokes}.
  # - Totals (regular matches): the RESULTS tab lists each player's final
  #   "Score". Players get "total" => strokes (nil if no score posted).
  #
  # Tabs are read by their header labels ("First and Last Name", "School",
  # "M/F", "Score"), since column order varies between sheets.
  #
  # Team rosters come from the ENTRIES tab: a school's team is its first block
  # of rows, ending at a medium/thick bottom border under the School column.
  # Rows for that school further down the tab play as individuals only.
  # Hole-by-hole sheets mark every team with a border, so a school without one
  # has no team; totals sheets list their teams under TEAM TOTALS instead.
  module Sheet
    GROUP_TAB = /\A\d+[AB]\z/
    SKIP_NAMES = ["Marshal"].freeze
    TEAM_BORDERS = %w[medium thick].freeze
    NAME = "First and Last Name"

    module_function

    def extract(path)
      book = RubyXL::Parser.parse(path)
      if book.worksheets.any? { |s| s.sheet_name.match?(GROUP_TAB) }
        extract_holes(book)
      elsif book["RESULTS"]
        extract_totals(book)
      else
        raise "#{path}: no group tabs (1A, 1B, ...) or RESULTS tab"
      end
    end

    def extract_holes(book)
      genders, teams = read_entries(tab(book, "ENTRIES"))
      players = {}
      book.worksheets.each do |sheet|
        read_group(sheet, players) if sheet.sheet_name.match?(GROUP_TAB)
      end
      roster = teams.select { |_, t| t["bordered"] }
      players.values.map { |p| with_entry(p, genders, roster) }
    end

    def extract_totals(book)
      genders, teams = read_entries(tab(book, "ENTRIES"))
      groups = read_pairings(book["PAIRINGS"])
      results = tab(book, "RESULTS")
      header, cols = header_row(results)
      name_c, school_c, score_c = cols.values_at(NAME, "School", "Score")
      raise "RESULTS: no Score column" unless score_c

      team_schools = read_team_totals(results, header, cols["Place"])
      players = []
      results.each_with_index do |row, r|
        next if r <= header || row.nil?
        name = clean_name(cell(row, name_c))
        school = norm(cell(row, school_c))
        next if name.empty? || school.empty?

        score = cell(row, score_c)
        players << { "name" => name, "school" => school, "group" => groups[name.downcase],
                     "total" => score.is_a?(Numeric) && score > 0 ? score.to_i : nil }
      end
      roster = teams.select { |school, _| team_schools.include?(school) }
      players.map { |p| with_entry(p, genders, roster) }
    end

    def with_entry(player, genders, roster)
      player.merge(
        "gender" => genders[player["name"].downcase],
        "team" => roster.fetch(player["school"], {}).fetch("players", []).include?(player["name"].downcase)
      )
    end

    def norm(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    # Drops notes like "(Needs to be in last group)", collapses spaces, and
    # capitalizes words typed all lowercase ("Nate fine" => "Nate Fine").
    def clean_name(value)
      norm(value.to_s.gsub(/\([^)]*\)/, " ")).split(" ").map { |w| w.match?(/\A[a-z]+\z/) ? w.capitalize : w }.join(" ")
    end

    def tab(book, name)
      book[name] or raise "no #{name} tab"
    end

    def cell(row, col)
      col && row[col]&.value
    end

    # [row index, {label => column index}] for the row starting a player table.
    # The first column wins when a label repeats (e.g. a second "School").
    def header_row(sheet)
      sheet.each_with_index do |row, r|
        next unless row
        labels = (0...row.cells.size).map { |c| norm(row[c]&.value) }
        next unless labels.include?(NAME)
        return [r, labels.each_with_index.reverse_each.to_h { |label, c| [label, c] }]
      end
      raise "#{sheet.sheet_name}: no '#{NAME}' header row"
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
        name = clean_name(first)
        next unless holes && !name.empty? && !SKIP_NAMES.include?(name)

        school = norm(row[1]&.value)
        player = players[[name, school]] ||= { "name" => name, "school" => school, "group" => sheet.sheet_name, "scores" => {} }
        holes.each_with_index do |hole, i|
          v = row[i + 2]&.value
          player["scores"][hole.to_s] = v.to_i if hole && v.is_a?(Numeric) && v > 0
        end
      end
    end

    # Returns [{lowercase name => gender}, {school => {"players" => [lowercase names], "bordered" => bool}}].
    def read_entries(sheet)
      header, cols = header_row(sheet)
      name_c, school_c, gender_c = cols.values_at(NAME, "School", "M/F")
      genders = {}
      teams = {}
      done = Set.new
      current = nil
      sheet.each_with_index do |row, r|
        next if r <= header || row.nil?
        name = clean_name(cell(row, name_c))
        school = norm(cell(row, school_c))
        genders[name.downcase] = norm(cell(row, gender_c)).then { |g| g.empty? ? nil : g } unless name.empty?
        next if school.empty?

        if school != current
          done << current if current
          current = school
        end
        next if done.include?(school)

        team = teams[school] ||= { "players" => [], "bordered" => false }
        team["players"] << name.downcase unless name.empty?
        if TEAM_BORDERS.include?(row[school_c]&.get_border(:bottom))
          team["bordered"] = true
          done << school
        end
      end
      [genders, teams]
    end

    # Schools listed under TEAM TOTALS: the column after "Place", down to the first blank.
    def read_team_totals(sheet, header, place_c)
      return Set.new unless place_c
      schools = Set.new
      sheet.each_with_index do |row, r|
        next if r <= header
        school = norm(row && cell(row, place_c + 1))
        break if school.empty?
        schools << school
      end
      schools
    end

    # {lowercase name => starting group number} from the PAIRINGS "Start" column.
    def read_pairings(sheet)
      return {} unless sheet
      header, cols = header_row(sheet)
      start_c, name_c = cols.values_at("Start", NAME)
      return {} unless start_c
      group = nil
      sheet.each_with_index.with_object({}) do |(row, r), groups|
        next if r <= header || row.nil?
        start = cell(row, start_c)
        group = start.to_i.to_s if start.is_a?(Numeric)
        name = clean_name(cell(row, name_c))
        groups[name.downcase] = group unless name.empty? || group.nil?
      end
    end
  end
end
