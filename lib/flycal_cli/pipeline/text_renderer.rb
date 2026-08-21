# frozen_string_literal: true

module FlycalCli
  module Pipeline
    # Shell text output — preserves the historical flycal search formatting.
    class TextRenderer < Renderer
      HOURS_PER_WORKING_DAY = Aggregator::HOURS_PER_WORKING_DAY

      def render(params)
        lines = []
        lines.concat(event_lines(params))
        lines << ""
        lines.concat(summary_lines(params))
        lines.join("\n") + "\n"
      end

      private

      def event_lines(params)
        Array(params[:events]).map do |ev|
          start_str = format_datetime(ev[:start_at])
          end_str = format_datetime(ev[:end_at])
          desc = ev[:summary] || "(no title)"
          if ev[:summary].nil? && ev[:description]
            desc = ev[:description].to_s.slice(0, 80)
          end
          "#{ev[:calendar_name]} | #{start_str} | #{end_str} | #{desc}"
        end
      end

      def summary_lines(params)
        totals = params[:totals] || {}
        time_min = params[:time_min]
        time_max = params[:time_max]
        from_str = time_min.strftime("%a %Y-%m-%d %H:%M")
        to_str = time_max.strftime("%a %Y-%m-%d %H:%M")

        lines = []
        lines << "---"
        lines << "From: #{from_str} | To: #{to_str}"
        lines << "Events found: #{totals[:event_count]}"
        lines << "Total time occupied: #{format_duration(totals[:total_minutes].to_f)}"
        lines << "Mock seed: #{params[:mock_seed]}" if params[:use_mock] && !params[:mock_seed].nil?

        case params[:group_by]
        when "week"
          lines << ""
          lines << "By week:"
          lines.concat(week_group_lines(params[:groups]))
        when "month"
          lines << ""
          lines << "By month:"
          lines.concat(month_group_lines(params[:groups]))
        end

        lines
      end

      def week_group_lines(groups)
        Array(groups).map do |g|
          start_str = format_date_with_day(g[:start_at])
          end_str = format_date_with_day(g[:period_label_end])
          "  #{bold(g[:index])}. #{start_str} - #{end_str}: #{format_hours_and_days(g[:hours], g[:working_days])}"
        end
      end

      def month_group_lines(groups)
        Array(groups).map do |g|
          start_str = format_date_with_day(g[:start_at])
          end_str = format_date_with_day(g[:period_label_end])
          "  #{g[:index]}. #{g[:month_name]} (#{start_str} - #{end_str}): #{format_hours_and_days(g[:hours], g[:working_days])}"
        end
      end

      def format_datetime(dt)
        return "-" if dt.nil?
        return dt if dt.is_a?(String)

        "#{Locale.day_abbr(dt)} #{dt.strftime("%Y-%m-%d %H:%M")}"
      end

      def format_date_with_day(dt)
        return "-" if dt.nil?

        t = dt.respond_to?(:to_time) ? dt.to_time : dt
        "#{Locale.day_abbr(t)} #{t.strftime("%Y-%m-%d")}"
      end

      def format_duration(total_minutes)
        hours = (total_minutes / 60).floor
        mins = (total_minutes % 60).round
        working_days = (total_minutes / 60.0 / HOURS_PER_WORKING_DAY).round(1)
        "#{bold(hours)}h #{bold(mins)}min (#{bold(working_days)} working days)"
      end

      def format_hours_and_days(hours, working_days)
        "#{bold(hours)}h (#{bold(working_days)} working days)"
      end

      def bold(str)
        "\e[1m#{str}\e[0m"
      end
    end
  end
end
