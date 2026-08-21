# frozen_string_literal: true

require "json"

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

      # Pretty JSON for --format json (EmCP / API friendly).
      def format_json(
        slots_by_day:,
        time_min:,
        time_max:,
        duration:,
        template:,
        calendars:,
        locale: nil,
        calendar_option: nil,
        from_option: nil,
        in_option: nil,
        free_before: nil,
        free_after: nil
      )
        items = []
        groups = slots_by_day.sort_by(&:first).map do |date, slots|
          slot_items = slots.map { |start_at, end_at| serialize_slot(start_at, end_at, date) }
          items.concat(slot_items)
          {
            "type" => "day",
            "key" => date.iso8601,
            "date" => date.iso8601,
            "from" => format_iso(slots.map(&:first).min),
            "to" => format_iso(slots.map(&:last).max),
            "slots_found" => slot_items.size,
            "items" => slot_items
          }
        end

        payload = {
          "params" => {
            "command" => "slots",
            "from" => format_iso(time_min),
            "to" => format_iso(time_max),
            "duration" => duration,
            "template" => template,
            "calendar" => blank_to_nil(calendar_option),
            "calendar_ids" => Array(calendars).map { |c| c[:id] },
            "format" => "json",
            "locale" => locale || Locale.current_locale,
            "from_option" => blank_to_nil(from_option),
            "in_option" => blank_to_nil(in_option),
            "free_before" => free_before,
            "free_after" => free_after
          }.compact,
          "info" => {
            "slots_found" => items.size,
            "from" => format_iso(time_min),
            "to" => format_iso(time_max),
            "duration" => duration,
            "template" => template,
            "calendars" => Array(calendars).map { |c| { "id" => c[:id], "name" => c[:name] } },
            "link" => google_calendar_day_url(time_min)
          },
          "items" => items,
          "groups" => groups
        }

        JSON.pretty_generate(payload) + "\n"
      end

      def strip_ansi(text)
        text.to_s.gsub(/\e\[[0-9;]*m/, "")
      end

      private

      def serialize_slot(start_at, end_at, date)
        {
          "date" => date.iso8601,
          "start" => { "dateTime" => format_iso(start_at) },
          "end" => { "dateTime" => format_iso(end_at) },
          "duration_seconds" => (end_at - start_at).to_i
        }
      end

      def format_iso(value)
        return nil if value.nil?
        return value.iso8601 if value.respond_to?(:iso8601)

        value.to_s
      end

      def blank_to_nil(value)
        str = value.to_s
        str.empty? ? nil : str
      end

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
