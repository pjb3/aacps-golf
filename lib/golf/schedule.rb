require "date"
require "time"

module Golf
  # When an event happens, from its front matter (date, optional end_date,
  # optional live, optional cancelled). Dates are compared in Eastern time;
  # callers set TZ=America/New_York (Jekyll does via `timezone`).
  module Schedule
    module_function

    def dates(event)
      first = event.fetch("date").to_date
      first..(event["end_date"]&.to_date || first)
    end

    # "today", "upcoming" or "past": which homepage section the event goes in.
    def section(event, today = Date.today)
      range = dates(event)
      return "today" if range.cover?(today)
      today < range.first ? "upcoming" : "past"
    end

    # Live events get the Live badge and are re-downloaded by the scheduled
    # build. That's every event happening today, unless its file says
    # `live: false` (e.g. results confirmed final); `live: true` forces it.
    def live?(event, today = Date.today, now = Time.now)
      return false if event["cancelled"]
      return false if event["live_until"] && now > Time.iso8601(event["live_until"])
      return event["live"] unless event["live"].nil?
      section(event, today) == "today"
    end
  end
end
