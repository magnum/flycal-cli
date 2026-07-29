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
    class_option :locale, type: :string, desc: "Override locale for this command (e.g. en, it)"

    def self.exit_on_failure?
      true
    end

    desc "login", "Connect to your Google account"
    def login
      apply_locale_override
      if Auth.logged_in?
        puts "✓ You are already connected to your Google account."
        puts "\nRun 'flycal config' to set the default calendar."
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
        puts "\nRun 'flycal config' to set the default calendar."
      rescue FlycalCli::Error => e
        puts "Error: #{e.message}"
        exit 1
      end
    end

    desc "logout", "Disconnect from Google account"
    def logout
      apply_locale_override
      unless Auth.logged_in?
        puts "You are not connected to any Google account."
        return
      end

      Auth.logout
      puts "✓ Disconnected successfully."
    end

    desc "calendars", "List available calendars"
    def calendars
      apply_locale_override
      unless Auth.logged_in?
        puts Locale.t("errors.not_connected")
        exit 1
      end

      calendars = load_calendars
      return if calendars.nil?

      calendars.each do |cal|
        summary = cal.summary || cal.id
        puts "#{summary} #{cal.id}"
      end
    end

    desc "config", "Configure flycal settings"
    def config
      apply_locale_override
      unless Auth.logged_in?
        puts Locale.t("errors.not_connected")
        exit 1
      end

      with_config_interrupt_handling do
        prompt = TTY::Prompt.new
        choice = prompt.select(
          Locale.t("config.prompt"),
          {
            Locale.t("config.options.calendar_default") => :calendar_default,
            Locale.t("config.options.exclude_calendars") => :exclude_calendars,
            Locale.t("config.options.edit_config") => :edit_config
          },
          per_page: 10
        )

        case choice
        when :calendar_default
          config_calendar_default
        when :exclude_calendars
          config_exclude_calendars
        when :edit_config
          config_edit
        end
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
      apply_locale_override
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

    desc "slots", "Find available time slots in your calendar"
    long_desc <<-LONGDESC
      List free time slots long enough for a given duration.

      Examples:
        flycal slots --in "3 days" --duration 1h
        flycal slots --in 1week --duration 30min -c Work
    LONGDESC
    option :duration, type: :string, required: true,
           desc: "Minimum slot length (e.g. 1h, 30 minutes, 1 hour)"
    option :in, type: :string, aliases: "-i", required: true,
           desc: "Search window from now (e.g. 3 days, 1 week, 48 hours)"
    option :calendar, type: :string, aliases: "-c", desc: "Calendar name or ID"
    def slots
      apply_locale_override
      unless Auth.logged_in?
        puts Locale.t("errors.not_connected")
        exit 1
      end

      begin
        slot_duration = DurationParser.to_seconds(options[:duration])
        time_min = Time.now
        time_max = DurationParser.add_to_time(options[:in], time_min)
        slot_cfg = Config.slots_config
        workhours = parse_workhours(slot_cfg["workhours"])
        weekdays_only = !!slot_cfg["weekdays_only"]
      rescue FlycalCli::Error => e
        puts "Error: #{e.message}"
        exit 1
      end

      if time_min >= time_max
        puts Locale.t("errors.duration_positive")
        exit 1
      end

      creds = Auth.credentials
      service = CalendarService.new(creds)

      exclude_calendar_ids = resolve_slots_exclude_calendar_ids(service, slot_cfg, options[:calendar])
      if exclude_calendar_ids.empty?
        puts Locale.t("slots.no_calendar")
        exit 1
      end

      events = exclude_calendar_ids.flat_map do |calendar_id|
        service.list_events(
          calendar_id,
          time_min: time_min,
          time_max: time_max
        )
      rescue Google::Apis::Errors::Error => e
        warn Locale.t("errors.calendar_fetch", calendar: calendar_id, message: e.message)
        []
      end

      finder = SlotFinder.new(
        events: events,
        time_min: time_min,
        time_max: time_max,
        slot_duration_seconds: slot_duration,
        workhours: workhours,
        weekdays_only: weekdays_only
      )

      output = SlotFormatter.format_output(finder.slots_by_day)
      puts output.empty? ? Locale.t("slots.no_available") : output
    end

    desc "update", "Update flycal-cli to the latest gem version"
    def update
      apply_locale_override
      puts "Updating flycal-cli..."
      success = system("gem", "update", "flycal-cli")
      return if success

      puts "Error: failed to update flycal-cli."
      exit 1
    end

    desc "version", "Show current flycal-cli version"
    def version
      apply_locale_override
      puts "flycal #{FlycalCli::VERSION}"
    end

    default_task :help

    private

    HOURS_PER_WORKING_DAY = 8

    def bold(str)
      "\e[1m#{str}\e[0m"
    end

    def bold_underline(str)
      "\e[1;4m#{str}\e[0m"
    end

    def apply_locale_override
      Locale.override!(options[:locale])
    end

    def with_config_interrupt_handling
      yield
    rescue Interrupt
      puts "\nconfig cancelled..."
      exit 0
    end

    def load_calendars
      creds = Auth.credentials
      service = CalendarService.new(creds)

      spinner = TTY::Spinner.new("#{Locale.t('common.loading_calendars')} ", format: :dots)
      spinner.auto_spin
      calendars = service.list_calendars
      spinner.stop("✓")

      if calendars.empty?
        puts Locale.t("errors.no_calendars")
        return nil
      end

      calendars
    end

    def calendar_choices(calendars, highlight_ids: [])
      highlights = Array(highlight_ids).compact
      calendars.to_h do |cal|
        primary = cal.primary ? " (primary)" : ""
        summary = cal.summary || cal.id
        label = "#{summary}#{primary}"
        label = bold_underline(label) if highlights.include?(cal.id)
        [label, cal.id]
      end
    end

    def choice_labels_for_ids(choices, calendar_ids)
      ids = Array(calendar_ids).compact
      choices.select { |_label, id| ids.include?(id) }.keys
    end

    def config_calendar_default
      calendars = load_calendars
      return if calendars.nil?

      prompt = TTY::Prompt.new
      default_id = Config.calendar_default
      selected_id = prompt.select(
        Locale.t("config.calendar_default.prompt"),
        calendar_choices(calendars, highlight_ids: [default_id]),
        per_page: 15,
        filter: true
      )

      calendar = calendars.find { |c| c.id == selected_id }
      return unless calendar

      Config.calendar_default = calendar.id
      puts Locale.t("config.calendar_default.saved", name: calendar.summary || calendar.id)
    end

    def config_exclude_calendars
      calendars = load_calendars
      return if calendars.nil?

      prompt = TTY::Prompt.new
      default_id = Config.calendar_default
      configured = Config.exclude_calendars
      current_ids = resolve_calendar_refs(calendars, configured)
      preselected_ids = current_ids.empty? && default_id ? [default_id] : current_ids
      choices = calendar_choices(calendars, highlight_ids: current_ids)
      preselected_labels = choice_labels_for_ids(choices, preselected_ids)

      selected_ids = prompt.multi_select(
        Locale.t("config.exclude_calendars.prompt"),
        choices,
        default: preselected_labels,
        min: 1,
        per_page: 15,
        filter: true
      )

      Config.exclude_calendars = selected_ids
      names = selected_ids.map do |id|
        calendars.find { |c| c.id == id }&.summary || id
      end
      puts Locale.t("config.exclude_calendars.saved", names: names.join(", "))
    end

    def config_edit
      editor = ENV["EDITOR"].to_s.strip
      editor = "vi" if editor.empty?

      success = system(editor, Config.config_file)
      puts Locale.t("config.edit.failed", editor: editor) unless success
    end

    def resolve_calendar_refs(calendars, refs)
      Array(refs).filter_map do |ref|
        resolve_calendar_ref(calendars, ref)
      end.uniq
    end

    def resolve_calendar_ref(calendars, ref)
      ref = ref.to_s.strip
      return nil if ref.empty?

      exact = calendars.find { |cal| cal.id == ref }
      return exact.id if exact

      matches = calendars.select do |cal|
        cal.id == ref ||
          (cal.summary && cal.summary.downcase.include?(ref.downcase))
      end

      matches.first&.id
    end

    def resolve_slots_exclude_calendar_ids(service, slot_cfg, calendar_override)
      configured = slot_cfg["exclude_calendars"]
      calendars = service.list_calendars

      refs = if configured.nil? || (configured.is_a?(Array) && configured.empty?)
               fallback = calendar_override || Config.calendar_default
               fallback ? [fallback] : []
             else
               configured
             end

      ids = resolve_calendar_refs(calendars, refs)
      return ids unless ids.empty?

      fallback = calendar_override || Config.calendar_default
      if fallback
        resolve_calendar_refs(calendars, [fallback])
      else
        primary = calendars.find(&:primary)
        primary ? [primary.id] : calendars.first(1).map(&:id)
      end
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

    def parse_hour_minute(value)
      match = value.to_s.strip.match(/\A(\d{1,2}):(\d{2})\z/)
      raise FlycalCli::Error, "Invalid time format #{value.inspect}. Use HH:MM (e.g. 9:00, 18:30)." unless match

      hour = match[1].to_i
      minute = match[2].to_i
      unless hour.between?(0, 23) && minute.between?(0, 59)
        raise FlycalCli::Error, "Invalid time #{value.inspect}. Hour must be 0-23 and minute 0-59."
      end

      [hour, minute]
    end

    def parse_workhours(values)
      ranges = Array(values).map do |item|
        start_str, end_str = item.to_s.strip.split("-", 2)
        raise FlycalCli::Error, "Invalid workhours item #{item.inspect}. Use format like '9-13' or '14:30-18:00'." if start_str.nil? || end_str.nil?

        sh, sm = parse_hour_minute_flexible(start_str)
        eh, em = parse_hour_minute_flexible(end_str)
        start_minutes = (sh * 60) + sm
        end_minutes = (eh * 60) + em
        raise FlycalCli::Error, "Invalid workhours range #{item.inspect}: end must be after start." if end_minutes <= start_minutes

        [sh, sm, eh, em]
      end

      raise FlycalCli::Error, "slots.workhours cannot be empty in config.yml." if ranges.empty?

      ranges.sort_by { |sh, sm, _eh, _em| (sh * 60) + sm }
    end

    def parse_hour_minute_flexible(value)
      str = value.to_s.strip
      if str.match?(/\A\d{1,2}\z/)
        hour = str.to_i
        raise FlycalCli::Error, "Invalid hour #{value.inspect}. Must be 0-23." unless hour.between?(0, 23)

        return [hour, 0]
      end

      parse_hour_minute(str)
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
        "#{Locale.day_abbr(dt)} #{dt.strftime("%Y-%m-%d %H:%M")}"
      end
    end

    def format_date_with_day(dt)
      return "-" if dt.nil?

      t = dt.respond_to?(:to_time) ? dt.to_time : dt
      "#{Locale.day_abbr(t)} #{t.strftime("%Y-%m-%d")}"
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
        month_name = "#{Locale.month_name(current)} #{current.year}"
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
