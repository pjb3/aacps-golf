require_relative "../lib/golf"

module Golf
  # Attaches computed standings to each event page as page.board, from the raw
  # scores in _data/scores/<event file name>.json. Events without a scores file
  # (not started yet) get no board.
  class LeaderboardGenerator < Jekyll::Generator
    safe true

    def generate(site)
      site.collections["events"].docs.each do |doc|
        name = doc.basename_without_ext
        doc.data["scores_key"] = name
        scores = site.data.dig("scores", name) or next
        doc.data["updated"] = scores["updated"]
        doc.data["board"] = Standings.new(scores["players"], pars: doc.data["pars"], par: doc.data["par"]).to_h
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
