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
      "w" => :weeks, "week" => :weeks, "weeks" => :weeks
    }.freeze

    class << self
      def parse(str)
        normalized = str.to_s.strip.downcase
        match = normalized.match(/\A(\d+(?:\.\d+)?)\s*([a-z]+)\z/) ||
                normalized.match(/\A(\d+(?:\.\d+)?)([a-z]+)\z/)
        raise FlycalCli::Error, invalid_message(str) unless match

        value = match[1].to_f
        unit = UNITS[match[2]]
        raise FlycalCli::Error, invalid_message(str) unless unit

        duration = value.public_send(unit)
        duration
      end

      def to_seconds(str)
        parse(str).to_i
      end

      def add_to_time(str, from_time)
        from_time + parse(str)
      end

      private

      def invalid_message(str)
        "Invalid duration: #{str.inspect}. Examples: 1h, 1 hour, 30 minutes, 3 days"
      end
    end
  end
end
