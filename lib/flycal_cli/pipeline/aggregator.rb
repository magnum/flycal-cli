# frozen_string_literal: true

require "active_support/core_ext/date"
require "active_support/core_ext/integer"
require "active_support/core_ext/time"

module FlycalCli
  module Pipeline
    # Second pipeline layer: group events and compute aggregate metrics.
    #
    # group_by is derived from the retrieved timeframe:
    #   day   — timeframe <= 7 days
    #   week  — timeframe > 7 days and <= 30 days
    #   month — timeframe > 30 days
    class Aggregator
      HOURS_PER_WORKING_DAY = 8

      def call(params)
        time_min = params[:time_min]
        time_max = params[:time_max]
        events = Array(params[:events])

        timeframe_days = (time_max - time_min) / 86400.0
        group_by = resolve_group_by(timeframe_days)

        params[:timeframe_days] = timeframe_days
        params[:group_by] = group_by

        ranges = events.filter_map do |ev|
          next if ev[:start_at].nil? || ev[:end_at].nil?

          [ev[:start_at], ev[:end_at]]
        end

        total_minutes = ranges.sum { |s, e| (e - s) / 60.0 }
        params[:totals] = {
          event_count: events.size,
          total_minutes: total_minutes,
          hours: (total_minutes / 60.0).floor,
          minutes: (total_minutes % 60).round,
          working_days: (total_minutes / 60.0 / HOURS_PER_WORKING_DAY).round(1)
        }

        params[:groups] =
          case group_by
          when "week" then weekly_groups(ranges, time_min, time_max)
          when "month" then monthly_groups(ranges, time_min, time_max)
          else daily_groups(ranges, time_min, time_max)
          end

        params
      end

      def self.resolve_group_by(timeframe_days)
        if timeframe_days > 30
          "month"
        elsif timeframe_days > 7
          "week"
        else
          "day"
        end
      end

      private

      def resolve_group_by(timeframe_days)
        self.class.resolve_group_by(timeframe_days)
      end

      def daily_groups(ranges, time_min, time_max)
        groups = []
        index = 1
        current = time_min.to_date
        end_date = time_max.to_date

        while current <= end_date
          day_start = [current.to_time, time_min].max
          day_end = [(current + 1).to_time, time_max].min
          mins = minutes_in_period(ranges, day_start, day_end)
          groups << build_group(
            index: index,
            key: current.strftime("%Y-%m-%d"),
            start_at: day_start,
            end_at: day_end,
            period_label_end: current,
            total_minutes: mins
          )
          index += 1
          current += 1
        end

        groups
      end

      def weekly_groups(ranges, time_min, time_max)
        groups = []
        index = 1
        current = time_min.to_date.beginning_of_week(:monday)

        while current.to_time < time_max
          week_start = [current.to_time, time_min].max
          week_end_date = current.end_of_week(:monday)
          week_end = [week_end_date.to_time + 1.day, time_max].min
          mins = minutes_in_period(ranges, week_start, week_end)
          groups << build_group(
            index: index,
            key: "W#{index}",
            start_at: week_start,
            end_at: week_end,
            period_label_end: week_end_date,
            total_minutes: mins
          )
          index += 1
          current += 7
        end

        groups
      end

      def monthly_groups(ranges, time_min, time_max)
        groups = []
        index = 1
        current = time_min.to_date.beginning_of_month
        end_date = time_max.to_date

        while current <= end_date
          month_start = current.beginning_of_month.to_time
          month_end = (current.end_of_month + 1.day).to_time
          period_start = [month_start, time_min].max
          period_end = [month_end, time_max].min
          mins = minutes_in_period(ranges, period_start, period_end)
          last_day = period_end.to_date - 1
          groups << build_group(
            index: index,
            key: current.strftime("%Y-%m"),
            start_at: period_start,
            end_at: period_end,
            period_label_end: last_day,
            total_minutes: mins,
            month_name: "#{Locale.month_name(current)} #{current.year}"
          )
          index += 1
          current = current.next_month.beginning_of_month
        end

        groups
      end

      def build_group(index:, key:, start_at:, end_at:, period_label_end:, total_minutes:, month_name: nil)
        {
          index: index,
          key: key,
          start_at: start_at,
          end_at: end_at,
          period_label_end: period_label_end,
          month_name: month_name,
          event_count: nil, # filled only when needed; minutes are overlap-based
          total_minutes: total_minutes,
          hours: (total_minutes / 60.0).round(1),
          working_days: (total_minutes / 60.0 / HOURS_PER_WORKING_DAY).round(1)
        }
      end

      def minutes_in_period(ranges, period_start, period_end)
        ranges.sum do |ev_start, ev_end|
          overlap_start = [ev_start, period_start].max
          overlap_end = [ev_end, period_end].min
          overlap_sec = overlap_end - overlap_start
          overlap_sec > 0 ? overlap_sec / 60.0 : 0
        end
      end
    end
  end
end
