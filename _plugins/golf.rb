require_relative "../lib/golf"

module Golf
  # For each event page, sets:
  # - page.section: "today", "upcoming" or "past" (as of the build; the
  #   scheduled workflow rebuilds shortly after midnight Eastern)
  # - page.is_live: see Schedule.live?
  # - page.par: from the event file, else the course's in _data/courses.yml
  # - page.board: standings from _data/scores/<event file name>.json, if any
  class LeaderboardGenerator < Jekyll::Generator
    safe true

    def generate(site)
      site.collections["events"].docs.each do |doc|
        data = doc.data
        data["section"] = Schedule.section(data)
        data["is_live"] = Schedule.live?(data)
        data["par"] ||= site.data.fetch("courses", {})[data["course"]] unless data["pars"]
        scores = site.data.dig("scores", doc.basename_without_ext) or next
        data["updated"] = scores["updated"]
        data["board"] = Standings.new(scores["players"], pars: data["pars"], par: data["par"]).to_h
      end
    end
  end

  module Filters
    # 0 => "E", 3 => "+3", -2 => "-2"
    def to_par(n)
      n.to_i.zero? ? "E" : format("%+d", n.to_i)
    end

    def to_par_class(n)
      n = n.to_i
      n.negative? ? "under" : (n.zero? ? "even" : "")
    end
  end
end

Liquid::Template.register_filter(Golf::Filters)
