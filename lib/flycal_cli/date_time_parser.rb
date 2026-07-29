# frozen_string_literal: true

require "date"
require "time"
require "active_support/core_ext/time"
require "active_support/core_ext/date"

module FlycalCli
  # Parses CLI date/time arguments in a locale-aware way.
  #
  # Always accepts ISO-like forms:
  #   YYYY-MM-DD, YYYY/MM/DD
  #   YYYY-MM-DDTHH:MM, YYYY-MM-DD HH:MM(:SS)
  #
  # With locale +it+: DD-MM-YYYY / DD/MM/YYYY (+ optional time)
  # With locale +en+ (default): MM-DD-YYYY / MM/DD/YYYY (+ optional time)
  class DateTimeParser
    TIME_SUFFIX = '(?:\s+|T)(\d{1,2}):(\d{2})(?::(\d{2}))?'.freeze

    class << self
      def parse(str, end_of_day: false, locale: nil)
        value = str.to_s.strip
        raise FlycalCli::Error, invalid_message(str) if value.empty?

        loc = (locale || Locale.current_locale).to_s
        formats = formats_for(loc)

        formats.each do |pattern, order|
          match = value.match(pattern)
          next unless match

          year, month, day, hour, min, sec = extract_parts(match, order)
          return build_time(year, month, day, hour, min, sec, end_of_day: end_of_day)
        end

        # Last resort: ISO8601 / Time.parse for full timestamps
        begin
          return Time.iso8601(value)
        rescue ArgumentError
          # fall through
        end

        begin
          parsed = Time.parse(value)
          return end_of_day && !time_component?(value) ? end_of_day_for(parsed.to_date) : parsed
        rescue ArgumentError
          raise FlycalCli::Error, invalid_message(str)
        end
      end

      def parse_or_default(str, default: Time.now, end_of_day: false, locale: nil)
        return default if str.nil? || str.to_s.strip.empty?

        parse(str, end_of_day: end_of_day, locale: locale)
      end

      private

      def formats_for(locale)
        iso = [
          [/\A(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})#{TIME_SUFFIX}\z/i, %i[year month day hour min sec]],
          [/\A(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})\z/, %i[year month day]]
        ]

        local =
          if locale == "it"
            [
              [/\A(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})#{TIME_SUFFIX}\z/i, %i[day month year hour min sec]],
              [/\A(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})\z/, %i[day month year]]
            ]
          else
            [
              [/\A(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})#{TIME_SUFFIX}\z/i, %i[month day year hour min sec]],
              [/\A(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})\z/, %i[month day year]]
            ]
          end

        iso + local
      end

      def extract_parts(match, order)
        parts = {}
        order.each_with_index do |key, idx|
          parts[key] = match[idx + 1]
        end

        [
          parts[:year].to_i,
          parts[:month].to_i,
          parts[:day].to_i,
          parts[:hour]&.to_i,
          parts[:min]&.to_i,
          parts[:sec]&.to_i
        ]
      end

      def build_time(year, month, day, hour, min, sec, end_of_day:)
        date = Date.new(year, month, day)

        if hour.nil?
          return end_of_day_for(date) if end_of_day
          return [date.to_time, Time.now].max if date == Date.today

          return date.to_time
        end

        Time.local(year, month, day, hour, min || 0, sec || 0)
      rescue ArgumentError
        raise FlycalCli::Error, "Invalid date: #{year}-#{month}-#{day}"
      end

      def end_of_day_for(date)
        Time.local(date.year, date.month, date.day, 23, 59, 59)
      end

      def time_component?(value)
        value.match?(/T|\d{1,2}:\d{2}/)
      end

      def invalid_message(str)
        if Locale.current_locale.to_s == "it"
          "Data non valida: #{str.inspect}. Usa YYYY-MM-DD, DD-MM-YYYY (anche con /) o con orario."
        else
          "Invalid date: #{str.inspect}. Use YYYY-MM-DD, MM-DD-YYYY (also with /), or with time."
        end
      end
    end
  end
end
