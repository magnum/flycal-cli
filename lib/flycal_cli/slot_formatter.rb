# frozen_string_literal: true

module FlycalCli
  class SlotFormatter
    class << self
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

      def day_header(date)
        "#{date.strftime('%A').downcase} #{date.day}/#{date.month}"
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
