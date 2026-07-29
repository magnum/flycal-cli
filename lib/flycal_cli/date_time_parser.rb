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
  # Relative forms (en + it):
  #   now, today/oggi, tomorrow/domani, yesterday/ieri
  #   monday / lunedi, next monday / prossimo lunedi, last friday / scorso venerdi
  #
  # With locale +it+: DD-MM-YYYY / DD/MM/YYYY (+ optional time)
  # With locale +en+ (default): MM-DD-YYYY / MM/DD/YYYY (+ optional time)
  class DateTimeParser
    TIME_SUFFIX = '(?:\s+|T)(\d{1,2}):(\d{2})(?::(\d{2}))?'.freeze

    # Ruby Date#wday: 0=Sunday ... 6=Saturday
    WEEKDAYS = {
      "sunday" => 0, "sun" => 0, "domenica" => 0, "dom" => 0,
      "monday" => 1, "mon" => 1, "lunedi" => 1, "lunedì" => 1, "lun" => 1,
      "tuesday" => 2, "tue" => 2, "martedi" => 2, "martedì" => 2, "mar" => 2,
      "wednesday" => 3, "wed" => 3, "mercoledi" => 3, "mercoledì" => 3, "mer" => 3,
      "thursday" => 4, "thu" => 4, "giovedi" => 4, "giovedì" => 4, "gio" => 4,
      "friday" => 5, "fri" => 5, "venerdi" => 5, "venerdì" => 5, "ven" => 5,
      "saturday" => 6, "sat" => 6, "sabato" => 6, "sab" => 6
    }.freeze

    NEXT_WORDS = %w[next prossimo prossima].freeze
    LAST_WORDS = %w[last scorso scorsa].freeze
    THIS_WORDS = %w[this questo questa].freeze

    class << self
      def parse(str, end_of_day: false, locale: nil)
        value = str.to_s.strip
        raise FlycalCli::Error, invalid_message(str) if value.empty?

        relative = parse_relative(value, end_of_day: end_of_day)
        return relative if relative

        loc = (locale || Locale.current_locale).to_s
        formats = formats_for(loc)

        formats.each do |pattern, order|
          match = value.match(pattern)
          next unless match

          year, month, day, hour, min, sec = extract_parts(match, order)
          return build_time(year, month, day, hour, min, sec, end_of_day: end_of_day)
        end

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

      def parse_relative(value, end_of_day:)
        normalized = value.downcase.strip
        normalized = normalized.tr("àèéìòù", "aeeiou")

        case normalized
        when "now", "adesso", "ora"
          return Time.now
        when "today", "oggi"
          return time_for_date(Date.today, end_of_day: end_of_day)
        when "tomorrow", "domani"
          return time_for_date(Date.today + 1, end_of_day: end_of_day)
        when "yesterday", "ieri"
          return time_for_date(Date.today - 1, end_of_day: end_of_day)
        end

        weekday = parse_weekday_phrase(normalized)
        return nil unless weekday

        time_for_date(weekday, end_of_day: end_of_day)
      end

      def parse_weekday_phrase(normalized)
        tokens = normalized.split(/\s+/)
        return nil if tokens.empty?

        qualifier = nil
        day_token = nil

        if tokens.length == 1
          day_token = tokens[0]
        elsif tokens.length == 2
          qualifier = tokens[0]
          day_token = tokens[1]
        else
          return nil
        end

        wday = WEEKDAYS[day_token]
        return nil unless wday

        today = Date.today

        if qualifier.nil? || THIS_WORDS.include?(qualifier)
          next_weekday(today, wday, inclusive: true)
        elsif NEXT_WORDS.include?(qualifier)
          next_weekday(today, wday, inclusive: false)
        elsif LAST_WORDS.include?(qualifier)
          previous_weekday(today, wday, inclusive: false)
        end
      end

      def next_weekday(from, wday, inclusive:)
        delta = (wday - from.wday) % 7
        delta = 7 if delta.zero? && !inclusive
        from + delta
      end

      def previous_weekday(from, wday, inclusive:)
        delta = (from.wday - wday) % 7
        delta = 7 if delta.zero? && !inclusive
        from - delta
      end

      def time_for_date(date, end_of_day:)
        return end_of_day_for(date) if end_of_day
        return [date.to_time, Time.now].max if date == Date.today

        date.to_time
      end

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
          return time_for_date(date, end_of_day: end_of_day)
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
          "Data non valida: #{str.inspect}. Usa YYYY-MM-DD, DD-MM-YYYY, oggi/domani, lunedi, prossimo lunedi, ecc."
        else
          "Invalid date: #{str.inspect}. Use YYYY-MM-DD, MM-DD-YYYY, today/tomorrow, monday, next monday, etc."
        end
      end
    end
  end
end
