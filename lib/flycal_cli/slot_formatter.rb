# frozen_string_literal: true

module FlycalCli
  class SlotFormatter
    class << self
      def format_header(from:, to:, duration:, calendars:, count:, template: nil)
        lines = []
        lines << Locale.t(
          "slots.header",
          count: underline(count),
          from: underline(Locale.format_long_date(from)),
          to: underline(Locale.format_long_date(to)),
          duration: underline(duration),
          template: underline(template.to_s)
        )
        calendars.each do |cal|
          lines << "- #{cal[:name]}"
        end
        lines << "link: #{google_calendar_day_url(from)}"
        lines.join("\n")
      end

      def format_output(slots_by_day)
        lines = []

        slots_by_day.sort_by(&:first).each do |date, slots|
          lines << "" unless lines.empty?
          lines << underline(day_header(date))
          slots.each do |start_at, end_at|
            lines << slot_range(start_at, end_at)
          end
        end

        lines.join("\n")
      end

      def strip_ansi(text)
        text.to_s.gsub(/\e\[[0-9;]*m/, "")
      end

      private

      def underline(str)
        "\e[4m#{str}\e[0m"
      end

      def google_calendar_day_url(from)
        t = from.respond_to?(:to_time) ? from.to_time : from
        "https://calendar.google.com/calendar/r/day/#{t.year}/#{t.month}/#{t.day}"
      end

      def day_header(date)
        "#{Locale.day_name(date)} #{date.day}/#{date.month}"
      end

      def slot_range(start_at, end_at)
        "#{format_time(start_at)} - #{format_time(end_at)}"
      end

      def format_time(time)
        return time.strftime("%-H") if time.min.zero?

        minutes = sprintf("%02d", time.min)
        "#{time.hour}.#{minutes}"
      end
    end
  end
end
