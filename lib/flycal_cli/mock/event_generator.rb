# frozen_string_literal: true

module FlycalCli
  module Mock
    # Builds deterministic fake calendar events from a Mock::Config.
    class EventGenerator
      EventStart = Struct.new(:date_time, :date, keyword_init: true)
      EventEnd = Struct.new(:date_time, :date, keyword_init: true)
      Event = Struct.new(:summary, :description, :start, :end, keyword_init: true)

      def initialize(config)
        @config = config
        @rng = Random.new(config.seed)
      end

      def generate
        counters = Hash.new(0)
        Array.new(@config.count) do
          pattern = @config.patterns.sample(random: @rng)
          counters[pattern] += 1
          title = "#{pattern}#{counters[pattern]}"
          start_at, end_at = random_range
          Event.new(
            summary: title,
            description: title,
            start: EventStart.new(date_time: start_at, date: nil),
            end: EventEnd.new(date_time: end_at, date: nil)
          )
        end.sort_by { |e| e.start.date_time }
      end

      private

      def random_range
        day = random_day
        duration = random_duration_seconds
        start_at = random_start_on(day, duration)
        [start_at, start_at + duration]
      end

      def random_day
        from_date = @config.range_from.to_date
        to_date = @config.range_to.to_date
        span = (to_date - from_date).to_i
        from_date + @rng.rand(0..span)
      end

      def random_duration_seconds
        min = @config.duration_min_seconds
        max = @config.duration_max_seconds
        return min if min == max

        @rng.rand(min..max)
      end

      def random_start_on(day, duration_seconds)
        from_h, from_m = @config.hours_from
        to_h, to_m = @config.hours_to
        window_start = day.to_time + (from_h * 3600) + (from_m * 60)
        window_end = day.to_time + (to_h * 3600) + (to_m * 60)
        latest_start = window_end - duration_seconds
        if latest_start < window_start
          raise FlycalCli::Error, "Mock event duration does not fit in the daily hours window."
        end

        span = (latest_start - window_start).to_i
        window_start + @rng.rand(0..span)
      end
    end
  end
end
