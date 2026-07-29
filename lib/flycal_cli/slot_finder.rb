# frozen_string_literal: true

module FlycalCli
  class SlotFinder
    DEFAULT_WORKHOURS = [[9, 0, 18, 0]].freeze
    STEP_SECONDS = 900

    def initialize(
      events:,
      time_min:,
      time_max:,
      slot_duration_seconds:,
      workhours: DEFAULT_WORKHOURS,
      weekdays_only: true,
      free_before_seconds: 0,
      free_after_seconds: 0
    )
      @events = events
      @time_min = time_min
      @time_max = time_max
      @slot_duration_seconds = slot_duration_seconds
      @workhours = workhours
      @weekdays_only = weekdays_only
      @free_before_seconds = free_before_seconds
      @free_after_seconds = free_after_seconds
    end

    def slots_by_day
      result = {}

      each_workday do |date|
        slots = []
        day_intervals(date).each do |day_start, day_end|
          next if day_end <= day_start

          busy = busy_intervals_for(date, day_start, day_end)
          gaps = free_gaps(day_start, day_end, busy)
          gaps.each do |gap_start, gap_end|
            slots.concat(slots_in_gap(gap_start, gap_end))
          end
        end
        result[date] = slots unless slots.empty?
      end

      result
    end

    private

    def each_workday
      date = @time_min.to_date
      end_date = @time_max.to_date

      while date <= end_date
        yield date if include_day?(date)
        date += 1
      end
    end

    def include_day?(date)
      return true unless @weekdays_only

      workday?(date)
    end

    def workday?(date)
      !date.saturday? && !date.sunday?
    end

    def day_intervals(date)
      @workhours.map do |start_h, start_m, end_h, end_m|
        start_at = Time.local(date.year, date.month, date.day, start_h, start_m, 0)
        end_at = Time.local(date.year, date.month, date.day, end_h, end_m, 0)
        start_at = [@time_min, start_at].max
        end_at = [@time_max, end_at].min
        [start_at, end_at]
      end
    end

    def busy_intervals_for(date, day_start, day_end)
      intervals = @events.filter_map do |event|
        interval_for_event(event, date, day_start, day_end)
      end
      merge_intervals(intervals.map { |start_at, end_at| pad_busy_interval(start_at, end_at) })
    end

    def pad_busy_interval(start_at, end_at)
      [
        start_at - @free_before_seconds,
        end_at + @free_after_seconds
      ]
    end

    def interval_for_event(event, date, day_start, day_end)
      return nil if event.status == "cancelled"
      return nil if event.transparency == "transparent"

      if event.start&.date
        event_date = Date.parse(event.start.date.to_s)
        event_end_date = Date.parse(event.end.date.to_s)
        return nil unless date >= event_date && date < event_end_date

        return [day_start, day_end]
      end

      start_at = to_time(event.start.date_time)
      end_at = to_time(event.end.date_time)
      return nil if end_at <= day_start || start_at >= day_end

      [[start_at, day_start].max, [end_at, day_end].min]
    end

    def merge_intervals(intervals)
      return [] if intervals.empty?

      sorted = intervals.sort_by(&:first)
      merged = [sorted.first]

      sorted[1..].each do |start_at, end_at|
        last_start, last_end = merged.last
        if start_at <= last_end
          merged[-1] = [last_start, [last_end, end_at].max]
        else
          merged << [start_at, end_at]
        end
      end

      merged
    end

    def free_gaps(day_start, day_end, busy)
      gaps = []
      cursor = day_start

      busy.each do |start_at, end_at|
        gaps << [cursor, start_at] if start_at > cursor
        cursor = [cursor, end_at].max
      end

      gaps << [cursor, day_end] if cursor < day_end
      gaps
    end

    def slots_in_gap(start_at, end_at)
      slots = []
      cursor = round_up_15(start_at)
      gap_limit = round_down_15(end_at)

      while cursor + @slot_duration_seconds <= gap_limit
        slots << [cursor, cursor + @slot_duration_seconds]
        cursor += STEP_SECONDS
      end

      slots
    end

    def round_up_15(time)
      sec = time.to_i
      remainder = sec % STEP_SECONDS
      return time if remainder.zero?

      Time.at(sec + (STEP_SECONDS - remainder))
    end

    def round_down_15(time)
      sec = time.to_i
      Time.at(sec - (sec % STEP_SECONDS))
    end

    def to_time(value)
      return value if value.is_a?(Time)
      return value.to_time if value.respond_to?(:to_time) && !value.is_a?(String)

      Time.parse(value.to_s)
    end
  end
end
