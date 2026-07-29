# frozen_string_literal: true

require "cgi"

module FlycalCli
  class SlotFormatter
    class << self
      def format_header(in_value:, duration:, calendars:)
        lines = []
        lines << Locale.t("slots.header", in: in_value, duration: duration)
        calendars.each do |cal|
          lines << calendar_link(cal[:name], cal[:id])
        end
        lines.join("\n")
      end

      def format_output(slots_by_day)
        lines = []

        slots_by_day.sort_by(&:first).each do |date, slots|
          lines << "" unless lines.empty?
          lines << day_header(date)
          slots.each do |start_at, end_at|
            lines << slot_range(start_at, end_at)
          end
        end

        lines.join("\n")
      end

      private

      def calendar_link(name, calendar_id)
        url = "https://calendar.google.com/calendar/r?cid=#{CGI.escape(calendar_id.to_s)}"
        # OSC 8 hyperlink (clickable in modern terminals)
        "\e]8;;#{url}\a#{name}\e]8;;\a"
      end

      def day_header(date)
        "#{Locale.day_name(date)} #{date.day}/#{date.month}"
      end

      def slot_range(start_at, end_at)
        "#{format_time(start_at)}-#{format_time(end_at)}"
      end

      def format_time(time)
        return time.strftime("%-H") if time.min.zero?

        minutes = sprintf("%02d", time.min)
        "#{time.hour}.#{minutes}"
      end
    end
  end
end
