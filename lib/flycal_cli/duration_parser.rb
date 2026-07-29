# frozen_string_literal: true

require "active_support/core_ext/numeric/time"
require "active_support/core_ext/integer/time"

module FlycalCli
  class DurationParser
    UNITS = {
      "s" => :seconds, "sec" => :seconds, "second" => :seconds, "seconds" => :seconds,
      "m" => :minutes, "min" => :minutes, "mins" => :minutes, "minute" => :minutes, "minutes" => :minutes,
      "h" => :hours, "hr" => :hours, "hour" => :hours, "hours" => :hours,
      "d" => :days, "day" => :days, "days" => :days,
      "w" => :weeks, "week" => :weeks, "weeks" => :weeks,
      "month" => :months, "months" => :months,
      "y" => :years, "year" => :years, "years" => :years
    }.freeze

    class << self
      def parse(str)
        normalized = str.to_s.strip.downcase
        match = normalized.match(/\A(\d+(?:\.\d+)?)\s*([a-z]+)\z/) ||
                normalized.match(/\A(\d+(?:\.\d+)?)([a-z]+)\z/)
        raise FlycalCli::Error, invalid_message(str) unless match

        value = match[1].to_f
        unit_key = match[2]
        unit = UNITS[unit_key]
        raise FlycalCli::Error, invalid_message(str) unless unit
        # Ambiguous bare "m": treat as minutes (not months)
        unit = :minutes if unit_key == "m"

        # months/years are Integer-only ActiveSupport extensions
        if %i[months years].include?(unit)
          value.to_i.public_send(unit)
        else
          value.public_send(unit)
        end
      end

      def to_seconds(str)
        parse(str).to_i
      end

      def add_to_time(str, from_time)
        from_time + parse(str)
      end

      private

      def invalid_message(str)
        "Invalid duration: #{str.inspect}. Examples: 1h, 30 minutes, 3 days, 1 week, 2 months, 1 year"
      end
    end
  end
end
