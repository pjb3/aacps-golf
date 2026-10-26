require "json"
require "nokogiri"
require "open-uri"
require_relative "schools"

module Golf
  # Reads one round of a Golf Genius event (the MPSSAA State Championship)
  # into the same player records Sheet produces for hole-by-hole events:
  # "name", "school", "group" (starting hole, e.g. "10A"), "scores"
  # ({hole => strokes}), "gender" and "team".
  #
  # The event's tournament results widget lists the round's tournaments. Ones
  # labelled Male or Female hold the individual leaderboards, whose players'
  # scorecards come from their detail pages. The Team tournament's detail
  # pages give each school's roster; its team scores are wrong (and Standings
  # works them out anyway), so only the rosters are used. Golf Genius doesn't
  # list schools for individual qualifiers; those players have no school
  # (bin/refresh fills in what it can from earlier events).
  #
  # Leaderboards and scorecards come back as JavaScript calls like
  # toggleEvent("<id>", "<html>", ...), not plain HTML.
  module GolfGenius
    BASE = "https://www.golfgenius.com"
    GENDERS = { "male" => "M", "female" => "F" }.freeze
    THREADS = 8

    module_function

    # league, round: ids from the results widget URL
    # (/leagues/<league>/widgets/tournament_results?round=<round>).
    # fetch: path => response body; replaced in tests.
    def extract(league:, round:, fetch: method(:get))
      widget = Nokogiri::HTML(fetch.call("/leagues/#{league}/widgets/tournament_results?shared=false&round=#{round}"))
      tournaments = widget.css("a.expand-tournament").map { |a| [a.text.strip, a["href"]] }
      raise "Golf Genius round #{round}: no tournaments listed" if tournaments.empty?

      groups = read_tee_sheet(fetch.call("/leagues/#{league}/widgets/next_round?shared=false&round=#{round}"))
      rosters = {}
      players = []
      tournaments.each do |label, href|
        rows = read_results(fetch.call(href))
        if label.match?(/\bteams?\b/i)
          parallel(rows) { |row| read_roster(fetch.call(details_path(row["id"]))) }
            .zip(rows).each { |names, row| names.each { |n| rosters[n] = Schools.canonical(row["name"]) } }
        elsif (gender = GENDERS[label[/\b(?:fe)?male\b/i].to_s.downcase])
          cards = parallel(rows) { |row| read_card(fetch.call(details_path(row["id"]))) }
          rows.zip(cards).each do |row, scores|
            player = { "name" => row["name"], "school" => nil, "group" => groups[row["name"]], "scores" => scores, "gender" => gender }
            player["status"] = row["status"] if row["status"] && scores.empty?
            players << player
          end
        end
      end
      raise "Golf Genius round #{round}: no Male or Female tournaments" if players.empty?

      players.map do |p|
        school = rosters[p["name"]]
        p.merge("school" => school, "team" => !school.nil?)
      end
    end

    # Widgets are plain HTML pages, unless asked for over XHR (then they're
    # JavaScript too); leaderboards and details only come back over XHR.
    def get(path)
      headers = { "User-Agent" => "Mozilla/5.0 (aacps-golf)" }
      headers.merge!("X-Requested-With" => "XMLHttpRequest", "Accept" => "text/javascript") unless path.include?("/widgets/")
      URI.open(BASE + path, headers, &:read).force_encoding("UTF-8")
    end

    def details_path(id) = "/tournaments2/details/#{id}"

    # A leaderboard: [{"id" => aggregate id, "name", "status" => "WD" etc.}].
    def read_results(body)
      js_html(body).css("tr.aggregate-row").map do |row|
        score = row.at_css("td.score")&.text.to_s.strip
        { "id" => row["data-aggregate-id"], "name" => clean(row["data-aggregate-name"]),
          "status" => score[/\A[A-Z]{2,}\z/] }
      end
    end

    # A player's detail page: {"hole" => strokes} for holes played.
    def read_card(body)
      line = js_html(body).at_css("tr.net-line") or return {}
      line.css("td.score").each_with_object({}) do |td, scores|
        hole = td["class"][/\bhole(\d+)\b/, 1]
        strokes = td.at_css(".score_box")&.text.to_s.strip
        scores[hole] = strokes.to_i if hole && strokes.match?(/\A\d+\z/) && strokes.to_i.positive?
      end
    end

    # A team's detail page: its players' names.
    def read_roster(body)
      js_html(body).css("tr.net-line").map { |line| clean(line["data-net-name"]) }
    end

    # The tee sheet's By Individual table: {name => starting hole, e.g. "10A"}.
    def read_tee_sheet(body)
      Nokogiri::HTML(body).css(".by_individual_table tr.player_row").to_h do |row|
        name = row.at_css("td.player_name").children.select(&:text?).map(&:text).join
        [clean(name), row.css("td")[2].text.strip]
      end
    end

    # The HTML in the second argument of a toggleEvent("<id>", "<html>", ...)
    # style call.
    def js_html(body)
      literal = body[/\(\s*"\d+",\s*"((?:[^"\\]|\\.)*)"/m, 1] or raise "Golf Genius: unexpected response #{body[0, 80].inspect}"
      Nokogiri::HTML.fragment(literal.gsub(/\\(u\h{4}|.)/m) do
        esc = Regexp.last_match(1)
        esc.size == 5 ? [esc[1..].hex].pack("U") : { "n" => "\n", "t" => "\t", "r" => "\r" }.fetch(esc, esc)
      end)
    end

    def clean(name) = name.to_s.gsub(/\s+/, " ").strip

    # Maps over items a few at a time, keeping their order.
    def parallel(items, &block)
      items.each_slice(THREADS).flat_map { |slice| slice.map { |item| Thread.new { block.call(item) } }.map(&:value) }
    end
  end
end
