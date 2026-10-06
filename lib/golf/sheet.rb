require "did_you_mean"
require "rubyXL"
require "rubyXL/convenience_methods"
require "set"
require_relative "schools"

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
  #   "Score". Players get "total" => strokes (nil if no score posted), plus
  #   "status" for entries like "DNS" and "note" for footnoted scores ("43*").
  #   Events with an empty TEAM TOTALS list are individual only.
  #
  # Tabs are read by their header labels ("First and Last Name", "School",
  # "M/F", "Score"), since column order varies between sheets.
  #
  # Team rosters come from the ENTRIES tab. A school's team is four to six
  # players from its first block of rows, ending at the last medium/thick
  # bottom border under the School column in that range (sheets also draw one
  # at the end of the school's list, below its individuals); with no such
  # border, the block's first six. Rows below that, or for the school further
  # down the tab, play as individuals only. In totals sheets, a player missing
  # from ENTRIES (a late substitute) plays for their school's team. Hole-by-hole sheets mark every team with
  # a border, so a school without one has no team; totals sheets list their
  # teams under TEAM TOTALS instead.
  #
  # Names are matched to ENTRIES loosely (same school, a letter or two apart),
  # since the tabs sometimes spell a player differently ("Giuliana"/"Juliana").
  module Sheet
    GROUP_TAB = /\A\d+[AB]\z/
    SKIP_NAMES = ["Marshal"].freeze
    TEAM_BORDERS = %w[medium thick].freeze
    TEAM_SIZE = 4..6
    NAME = "First and Last Name"

    module_function

    def extract(path, team_event: false)
      book = RubyXL::Parser.parse(path)
      if book.worksheets.any? { |s| s.sheet_name.match?(GROUP_TAB) }
        extract_holes(book)
      elsif book["RESULTS"]
        extract_totals(book, team_event: team_event)
      else
        raise "#{path}: no group tabs (1A, 1B, ...) or RESULTS tab"
      end
    end

    def extract_holes(book)
      entries = read_entries(tab(book, "ENTRIES"))
      players = {}
      book.worksheets.each do |sheet|
        read_group(sheet, players) if sheet.sheet_name.match?(GROUP_TAB)
      end
      players.values.map { |p| with_entry(p, entries) { |e| e["bordered"] } }
    end

    def extract_totals(book, team_event: false)
      entries = read_entries(tab(book, "ENTRIES"))
      groups = read_pairings(book["PAIRINGS"])
      results = tab(book, "RESULTS")
      first_header, header, cols = header_rows(results)
      name_c, school_c, score_c = cols.values_at(NAME, "School", "Score")
      raise "RESULTS: no Score column" unless score_c

      team_schools = read_team_totals(results, first_header, cols["Place"])
      # Live team matches may not populate TEAM TOTALS until play is over.
      team_schools = entries.map { |e| e["school"] }.reject(&:empty?).to_set if team_event && team_schools.empty?
      footnotes = read_footnotes(results, header, name_c)
      players = []
      results.each_with_index do |row, r|
        next if r <= header || row.nil?
        name = clean_name(cell(row, name_c))
        school = clean_school(cell(row, school_c))
        next if name.empty? || school.empty?

        total, mark, status = parse_score(cell(row, score_c))
        player = { "name" => name, "school" => school, "group" => groups[name.downcase], "total" => total }
        player["status"] = status if status
        player.merge!("mark" => mark, "note" => footnotes[mark]) if mark
        players << player
      end
      team_schools = team_schools.map { |t| match_school(t, players.map { |p| p["school"] }.uniq) }
      players.map do |p|
        with_entry(p, entries) { |e| team_schools.include?(e["school"]) }
          .tap { |q| q["team"] = team_schools.include?(q["school"]) unless find_entry(p, entries) }
      end
    end

    # Adds "gender" and "team" from the player's ENTRIES row. The block says
    # whether that row's school fields a team at this event.
    def with_entry(player, entries)
      entry = find_entry(player, entries)
      player.merge(
        "gender" => entry&.fetch("gender"),
        "team" => !entry.nil? && entry["team"] && yield(entry)
      )
    end

    def find_entry(player, entries)
      name, school = player["name"].downcase, player["school"]
      same_school = entries.select { |e| e["school"] == school }
      same_school.find { |e| e["key"] == name } ||
        entries.find { |e| e["key"] == name } ||
        Schools.unique(same_school.select { |e| DidYouMean::Levenshtein.distance(e["key"], name) <= 2 })
    end

    # A TEAM TOTALS label ("SP", "Glen Birnie") as one of the players' schools.
    def match_school(label, schools)
      return label if schools.include?(label)
      Schools.unique(schools.select { |s| Schools.initials(s) == label || DidYouMean::Levenshtein.distance(s.downcase, label.downcase) <= 2 }) || label
    end

    def norm(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    # Drops notes like "(Needs to be in last group)" and stray symbols
    # ("Emily Willis+"), collapses spaces, and capitalizes words typed all
    # lowercase ("Nate fine" => "Nate Fine").
    def clean_name(value)
      capitalize_lowercase(norm(value.to_s.gsub(/\([^)]*\)/, " ").gsub(/[^\p{L}\s.'-]/, "")))
    end

    # "Severna park" => "Severna Park", "CSP" => "Chesapeake Science Point"
    def clean_school(value)
      name = capitalize_lowercase(norm(value))
      name.empty? ? name : Schools.canonical(name)
    end

    def capitalize_lowercase(text)
      text.split(" ").map { |w| w.match?(/\A[a-z]+\z/) ? w.capitalize : w }.join(" ")
    end

    # A RESULTS score cell: 42, "43*" (footnoted, e.g. lost card) or a status
    # like "DNS". Returns [strokes or nil, footnote mark or nil, status or nil].
    def parse_score(value)
      case value
      when Numeric then [value.positive? ? value.to_i : nil, nil, nil]
      when /\A\s*(\d+)\s*(\*+)?\s*\z/ then [$1.to_i, $2, nil]
      when /\A\s*([A-Za-z]+)\s*\z/ then [nil, nil, $1.upcase]
      else [nil, nil, nil]
      end
    end

    # Footnote rows under the player list, e.g. "*Lost card*" => {"*" => "Lost card"}.
    def read_footnotes(sheet, header, name_c)
      notes = {}
      sheet.each_with_index do |row, r|
        next if r <= header || row.nil?
        notes[$1] = $2.strip if norm(cell(row, name_c)) =~ /\A(\*+)\s*(.+?)\**\z/
      end
      notes
    end

    def tab(book, name)
      book[name] or raise "no #{name} tab"
    end

    def cell(row, col)
      col && row[col]&.value
    end

    HEADER_LABELS = [NAME, "Grade", "School", "M/F", "Score", "Place", "Start"].freeze

    # [first header row, last header row, {label => column index}] for a
    # player table. Some tabs have a second, newer header row further down
    # with the columns rearranged; later rows' labels win. Within a row the
    # first column wins when a label repeats (e.g. a second "School").
    def header_rows(sheet)
      rows = []
      sheet.each_with_index do |row, r|
        next unless row
        labels = (0...row.cells.size).map { |c| norm(row[c]&.value) }
        rows << [r, labels] if labels.include?(NAME)
      end
      raise "#{sheet.sheet_name}: no '#{NAME}' header row" if rows.empty?
      cols = {}
      rows.each do |_, labels|
        labels.each_with_index.reverse_each { |label, c| cols[label] = c if HEADER_LABELS.include?(label) }
      end
      [rows.first[0], rows.last[0], cols]
    end

    def header_row(sheet)
      _, last, cols = header_rows(sheet)
      [last, cols]
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

        school = clean_school(row[1]&.value)
        player = players[[name, school]] ||= { "name" => name, "school" => school, "group" => sheet.sheet_name, "scores" => {} }
        holes.each_with_index do |hole, i|
          v = row[i + 2]&.value
          player["scores"][hole.to_s] = v.to_i if hole && v.is_a?(Numeric) && v > 0
        end
      end
    end

    # One hash per ENTRIES row with a name: "name", "key" (lowercase name),
    # "school", "gender", "team" (in the school's team block) and "bordered"
    # (the school marks its team with a border).
    def read_entries(sheet)
      header, cols = header_row(sheet)
      name_c, school_c, gender_c = cols.values_at(NAME, "School", "M/F")
      entries = []
      blocks = {} # school => {"rows" => [entry or nil], "last_border" => index}
      current = nil
      sheet.each_with_index do |row, r|
        next if r <= header || row.nil?
        name = clean_name(cell(row, name_c))
        school = clean_school(cell(row, school_c))
        next if name.empty? && school.empty?

        entry = name.empty? ? nil : { "name" => name, "key" => name.downcase, "school" => school,
                                     "gender" => norm(cell(row, gender_c)).then { |g| g.empty? ? nil : g },
                                     "team" => false, "bordered" => false }
        entries << entry if entry
        next if school.empty?

        # Only the school's first contiguous block of rows can be its team.
        first_block = school == current || !blocks.key?(school)
        current = school
        next unless first_block

        block = blocks[school] ||= { "rows" => [], "last_border" => nil }
        block["rows"] << entry
        border = TEAM_BORDERS.include?(row[school_c]&.get_border(:bottom))
        block["last_border"] = block["rows"].size - 1 if border && TEAM_SIZE.cover?(block["rows"].compact.size)
      end
      blocks.each_value do |block|
        cut = block["last_border"]
        team = cut ? block["rows"][0..cut].compact : block["rows"].compact.first(TEAM_SIZE.max)
        team.each { |e| e.merge!("team" => true, "bordered" => !cut.nil?) }
      end
      entries
    end

    # Schools listed under TEAM TOTALS: the column after "Place", down to the first blank.
    def read_team_totals(sheet, header, place_c)
      return Set.new unless place_c
      schools = Set.new
      sheet.each_with_index do |row, r|
        next if r <= header
        school = clean_school(row && cell(row, place_c + 1))
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
