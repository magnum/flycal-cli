# frozen_string_literal: true

require "thor"
require "time"
require "date"
require "active_support/core_ext/date"
require "active_support/core_ext/integer"
require "active_support/core_ext/time"
require "tty-prompt"
require "tty-spinner"

module FlycalCli
  class Cli < Thor
    package_name "flycal"

    def self.exit_on_failure?
      true
    end

    desc "login", "Connect to your Google account"
    def login
      if Auth.logged_in?
        puts "✓ You are already connected to your Google account."
        puts "\nRun 'flycal calendars' to set the default calendar."
        return
      end

      unless Config.credentials_exist?
        puts "Error: Credentials file not found."
        puts "\nTo configure flycal:"
        puts "1. Go to https://console.cloud.google.com/apis/credentials"
        puts "2. Create 'Desktop app' credentials"
        puts "3. Download the JSON and save it as: #{Config.credentials_path}"
        puts "\nAlso add this URI as an authorized redirect:"
        puts "  http://127.0.0.1:9292/oauth2callback"
        return
      end

      begin
        Auth.login
        puts "\n✓ Authentication completed successfully!"
        puts "\nRun 'flycal calendars' to set the default calendar."
      rescue FlycalCli::Error => e
        puts "Error: #{e.message}"
        exit 1
      end
    end

    desc "logout", "Disconnect from Google account"
    def logout
      unless Auth.logged_in?
        puts "You are not connected to any Google account."
        return
      end

      Auth.logout
      puts "✓ Disconnected successfully."
    end

    desc "calendars", "List available calendars and set the default one"
    def calendars
      unless Auth.logged_in?
        puts "You are not connected. Run 'flycal login' first."
        exit 1
      end

      creds = Auth.credentials
      service = CalendarService.new(creds)

      spinner = TTY::Spinner.new("Loading calendars... ", format: :dots)
      spinner.auto_spin
      calendars = service.list_calendars
      spinner.stop("✓")

      if calendars.empty?
        puts "No calendars found."
        return
      end

      # Build selection list (display => calendar_id)
      default_id = Config.calendar_default
      choices = calendars.to_h do |cal|
        primary = cal.primary ? " (primary)" : ""
        default = (cal.id == default_id) ? " [default]" : ""
        summary = cal.summary || cal.id
        label = "#{summary}#{primary}#{default}"
        [label, cal.id]
      end

      prompt = TTY::Prompt.new
      selected_id = prompt.select(
        "Choose the default calendar:",
        choices,
        per_page: 15,
        filter: true
      )

      calendar = calendars.find { |c| c.id == selected_id }
      if calendar
        Config.calendar_default = calendar.id
        puts "\n✓ Default calendar set to: #{calendar.summary}"
      end
    end

    desc "search", "Search for events in calendars"
    long_desc <<-LONGDESC
      Search for events in your Google calendar(s).

      Time range:
        -f, --from DATE   Start (default: today midnight)
        -t, --to DATE     End (default: 23:59 of day 30)
        -i, --in DURATION Duration from --from, overrides --to.
                          Format: 30days, 48hours, 2months, 1year (no space).
                          With space use quotes: --in "30 days"

      Examples:
        flycal search
        flycal search --in 30days -d placeholder
        flycal search -i 1months --description placeholder
        flycal search -f 2025-03-01 --in 2months
    LONGDESC
    option :calendar, type: :string, aliases: "-c", desc: "Calendar name or ID"
    option :from, type: :string, aliases: "-f", desc: "Start (default: today midnight)"
    option :to, type: :string, aliases: "-t", desc: "End (default: 23:59 of day 30)"
    option :in, type: :string, aliases: "-i", desc: "Duration: 30days, 48hours, 2months, 1year (overrides --to)"
    option :description, type: :string, aliases: "-d", desc: "Filter by text in event"
    def search
      unless Auth.logged_in?
        puts "You are not connected. Run 'flycal login' first."
        exit 1
      end

      time_min = options[:from].to_s.empty? ? Date.today.to_time : parse_datetime(options[:from])
      begin
        time_max = if options[:in].to_s.empty?
                     options[:to].to_s.empty? ? (Date.today + 30).to_time + 86400 - 1 : parse_datetime(options[:to], end_of_day: true)
                   else
                     parse_duration_in(options[:in], time_min)
                   end
      rescue FlycalCli::Error => e
        puts "Error: #{e.message}"
        exit 1
      end

      if time_min > time_max
        puts "Error: 'from' date must be before 'to' date."
        exit 1
      end

      creds = Auth.credentials
      service = CalendarService.new(creds)

      calendar_ids = resolve_calendar_ids(service, options[:calendar])
      if calendar_ids.empty?
        puts "No calendars found."
        exit 1
      end

      events = service.list_all_events(
        calendar_ids,
        time_min: time_min,
        time_max: time_max,
        query: options[:description]
      )

      print_events(service, events)
      print_search_summary(events, time_min: time_min, time_max: time_max)
    end

    default_task :help

    private

    HOURS_PER_WORKING_DAY = 8

    def bold(str)
      "\e[1m#{str}\e[0m"
    end

    def parse_datetime(str, end_of_day: false)
      return nil if str.nil? || str.empty?

      if str.include?("T")
        Time.parse(str)
      else
        d = Date.parse(str)
        t = d.to_time
        end_of_day ? t + 86400 - 1 : t  # 23:59:59 for --to when date-only
      end
    end

    def parse_duration_in(str, from_time)
      # Support both "30days" and "30 days" (no space avoids shell splitting)
      m = str.to_s.strip.match(/\A(\d+)\s*(day|days|d|hour|hours|h|month|months|m|year|years|y)\z/i)
      raise FlycalCli::Error, "Invalid --in format. Use: 30days, 48hours, 2months, 1year (no space, or quote: --in \"30 days\")" unless m

      n = m[1].to_i
      unit = m[2].downcase

      case unit
      when "hour", "hours", "h"
        from_time + n * 3600
      when "day", "days", "d"
        from_time + n * 86400
      when "month", "months", "m"
        (from_time.to_date >> n).to_time + (from_time.hour * 3600 + from_time.min * 60 + from_time.sec)
      when "year", "years", "y"
        (from_time.to_date >> (n * 12)).to_time + (from_time.hour * 3600 + from_time.min * 60 + from_time.sec)
      else
        raise FlycalCli::Error, "Invalid unit: #{unit}. Use: days, hours, months, years"
      end
    end

    def resolve_calendar_ids(service, calendar_name)
      calendar_lists = service.list_calendars

      if calendar_name.nil? || calendar_name.empty?
        default_id = Config.calendar_default
        if default_id
          return [default_id]
        end
        # Use primary calendar if available
        primary = calendar_lists.find(&:primary)
        return [primary.id] if primary
        # Otherwise first calendar
        return [calendar_lists.first.id] if calendar_lists.any?
        return []
      end

      # Search by name or ID
      matches = calendar_lists.select do |cal|
        cal.id == calendar_name ||
          (cal.summary && cal.summary.downcase.include?(calendar_name.downcase))
      end

      matches.map(&:id)
    end

    def print_events(service, events)
      # Use calendar list for names (avoids extra API calls)
      calendar_list = service.list_calendars
      calendar_names = calendar_list.to_h { |c| [c.id, c.summary || c.id] }

      events.each do |item|
        cal_id = item[:calendar_id]
        event = item[:event]
        cal_name = calendar_names[cal_id] || cal_id

        start_time = event.start&.date_time || event.start&.date
        end_time = event.end&.date_time || event.end&.date

        start_str = format_datetime(start_time)
        end_str = format_datetime(end_time)
        desc = event.summary || "(no title)"
        desc = event.description&.slice(0, 80) if event.summary.nil? && event.description

        puts "#{cal_name} | #{start_str} | #{end_str} | #{desc}"
      end
    end

    def format_datetime(dt)
      return "-" if dt.nil?

      if dt.is_a?(String)
        dt
      else
        dt.strftime("%a %Y-%m-%d %H:%M")
      end
    end

    def format_date_with_day(dt)
      return "-" if dt.nil?

      t = dt.respond_to?(:to_time) ? dt.to_time : dt
      t.strftime("%a %Y-%m-%d")
    end

    def print_search_summary(events, time_min:, time_max:)
      event_ranges = extract_event_ranges(events)
      total_minutes = event_ranges.sum { |s, e| (e - s) / 60 }

      from_str = time_min.strftime("%a %Y-%m-%d %H:%M")
      to_str = time_max.strftime("%a %Y-%m-%d %H:%M")

      puts "\n---"
      puts "From: #{from_str} | To: #{to_str}"
      puts "Events found: #{events.size}"
      puts "Total time occupied: #{format_duration(total_minutes)}"

      frame_days = (time_max - time_min) / 86400.0
      if frame_days > 30
        print_monthly_breakdown(event_ranges, time_min, time_max)
      elsif frame_days > 7
        print_weekly_breakdown(event_ranges, time_min, time_max)
      end
    end

    def extract_event_ranges(events)
      events.filter_map do |item|
        event = item[:event]
        start_t = event.start&.date_time || event.start&.date
        end_t = event.end&.date_time || event.end&.date
        next if start_t.nil? || end_t.nil?

        start_t = start_t.to_time if start_t.respond_to?(:to_time)
        end_t = end_t.to_time if end_t.respond_to?(:to_time)
        [start_t, end_t]
      end
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

    def minutes_in_period(event_ranges, period_start, period_end)
      event_ranges.sum do |ev_start, ev_end|
        overlap_start = [ev_start, period_start].max
        overlap_end = [ev_end, period_end].min
        overlap_sec = overlap_end - overlap_start
        overlap_sec > 0 ? overlap_sec / 60.0 : 0
      end
    end

    def print_weekly_breakdown(event_ranges, time_min, time_max)
      puts "\nBy week:"
      week_num = 1
      current = time_min.to_date.beginning_of_week(:monday)
      while current.to_time < time_max
        week_start = [current.to_time, time_min].max
        week_end_date = current.end_of_week(:monday)
        week_end = [week_end_date.to_time + 1.day, time_max].min
        mins = minutes_in_period(event_ranges, week_start, week_end)
        hours = (mins / 60).round(1)
        working_days = (mins / 60.0 / HOURS_PER_WORKING_DAY).round(1)
        start_str = format_date_with_day(week_start)
        end_str = format_date_with_day(week_end_date)
        puts "  #{bold(week_num)}. #{start_str} - #{end_str}: #{format_hours_and_days(hours, working_days)}"
        week_num += 1
        current = current + 7.days
      end
    end

    def print_monthly_breakdown(event_ranges, time_min, time_max)
      puts "\nBy month:"
      month_num = 1
      current = time_min.to_date.beginning_of_month
      end_date = time_max.to_date

      while current <= end_date
        month_start = current.beginning_of_month.to_time
        month_end = (current.end_of_month + 1.day).to_time
        period_start = [month_start, time_min].max
        period_end = [month_end, time_max].min

        mins = minutes_in_period(event_ranges, period_start, period_end)
        hours = (mins / 60).round(1)
        working_days = (mins / 60.0 / HOURS_PER_WORKING_DAY).round(1)
        month_name = current.strftime("%B %Y")
        start_str = format_date_with_day(period_start)
        last_day = (period_end.to_date - 1.day)
        end_str = format_date_with_day(last_day)
        puts "  #{month_num}. #{month_name} (#{start_str} - #{end_str}): #{format_hours_and_days(hours, working_days)}"
        month_num += 1
        current = current.next_month.beginning_of_month
      end
    end
  end
end
