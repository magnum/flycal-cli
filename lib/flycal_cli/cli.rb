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
    class_option :format, type: :string, default: "text",
                 desc: "Output format: text or json"

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

      Mock mode (no Google API; triggered by --mockCalendar or --mockTemplate):
        --mockTemplate NAME   Load defaults from mocks/ or mockTemplates/NAME.json
        --mockCalendar NAME   Mock calendar id/name (required here or in template)
        --mockSeed N          Reproducible random distribution
        --mockEventCount N
        --mockEventFrom/--mockEventTo
        --mockEventDescriptionPatterns a,b,c
        --mockEventDurationMin/--mockEventDurationMax
        --mockEventHoursFrom/--mockEventHoursTo

      Examples:
        flycal search
        flycal search --in 30days -d placeholder
        flycal search -i 1months --description placeholder
        flycal search -f 2025-03-01 --in 2months
        flycal search --mockTemplate mock1 --description work --calendar mock1
        flycal search -d "rui|solver" --groupBy description --format json
    LONGDESC
    option :calendar, type: :string, aliases: "-c", desc: "Calendar name or ID"
    option :from, type: :string, aliases: "-f", desc: "Start (default: today midnight)"
    option :to, type: :string, aliases: "-t", desc: "End (default: 23:59 of day 30)"
    option :in, type: :string, aliases: "-i", desc: "Duration: 30days, 48hours, 2months, 1year (overrides --to)"
    option :description, type: :string, aliases: "-d",
           desc: "Filter text in event (OR with |, e.g. rui|solver)"
    option :groupBy, type: :string,
           desc: "Grouping: day, week, month, or description (default: auto from timeframe)"
    option :mockTemplate, type: :string, desc: "Load mock defaults from mocks/<name>.json"
    option :mockCalendar, type: :string, desc: "Use a generated mock calendar (skips Google API)"
    option :mockSeed, type: :numeric, desc: "Seed for reproducible mock events"
    option :mockEventDescriptionPatterns, type: :string, desc: "Comma-separated title patterns (e.g. work,personal)"
    option :mockEventCount, type: :numeric, desc: "Number of mock events to generate"
    option :mockEventFrom, type: :string, desc: "Mock events start date"
    option :mockEventTo, type: :string, desc: "Mock events end date"
    option :mockEventDurationMin, type: :string, desc: "Min mock event duration (e.g. 4h)"
    option :mockEventDurationMax, type: :string, desc: "Max mock event duration (e.g. 4h)"
    option :mockEventHoursFrom, type: :string, desc: "Daily start window for mock events (HH:MM)"
    option :mockEventHoursTo, type: :string, desc: "Daily end window for mock events (HH:MM)"
    def search
      apply_locale_override

      mock_mode = Mock::Config.enabled?(options)
      mock_config = nil
      if mock_mode
        begin
          mock_config = Mock::Config.from_options(options)
        rescue FlycalCli::Error => e
          puts "Error: #{e.message}"
          exit 1
        end
      elsif !Auth.logged_in?
        puts "You are not connected. Run 'flycal login' first."
        exit 1
      end

      time_min = options[:from].to_s.empty? ? Date.today.to_time : DateTimeParser.parse(options[:from])
      begin
        time_max = if options[:in].to_s.empty?
                     options[:to].to_s.empty? ? (Date.today + 30).to_time + 86400 - 1 : DateTimeParser.parse(options[:to], end_of_day: true)
                   else
                     DurationParser.add_to_time(options[:in], time_min)
                   end
      rescue FlycalCli::Error => e
        puts "Error: #{e.message}"
        exit 1
      end

      if time_min > time_max
        puts "Error: 'from' date must be before 'to' date."
        exit 1
      end

      service =
        if mock_config
          Mock::CalendarService.new(mock_config)
        else
          CalendarService.new(Auth.credentials)
        end

      calendar_ids =
        if mock_config && options[:calendar].to_s.empty?
          [mock_config.calendar_name]
        else
          resolve_calendar_ids(service, options[:calendar])
        end
      if calendar_ids.empty?
        puts "No calendars found."
        exit 1
      end

      params = Pipeline::Params.new(
        command: "search",
        time_min: time_min,
        time_max: time_max,
        calendar_ids: calendar_ids,
        description: options[:description],
        calendar: options[:calendar],
        from_option: options[:from],
        to_option: options[:to],
        in_option: options[:in],
        group_by_option: options[:groupBy],
        format: options[:format] || "text",
        locale: Locale.current_locale,
        use_mock: !mock_config.nil?,
        mock_seed: mock_config&.seed,
        mock_calendar: mock_config&.calendar_name,
        mock_template: mock_config&.template_name
      )

      begin
        output = Pipeline::SearchPipeline.new(service).run(params)
        print output
      rescue FlycalCli::Error => e
        puts "Error: #{e.message}"
        exit 1
      end
    end

    desc "slots", "Find available time slots in your calendar"
    long_desc <<-LONGDESC
      List free time slots long enough for a given duration.

      Defaults:
        --from      from config (default: now)
        --in        1 week
        --duration  from config (default: 45min)
        --template  first template in config (default: work)

      Examples:
        flycal slots
        flycal slots --in "5 days"
        flycal slots --in "12 days" --template dinner
        flycal slots --duration 1h --from 2026-08-01
    LONGDESC
    option :duration, type: :string,
           desc: "Slot length (default from config: slots.defaults.default_duration)"
    option :in, type: :string, aliases: "-i", default: "1 week",
           desc: "Search window from --from (default: 1 week)"
    option :from, type: :string, aliases: "-f",
           desc: "Start (default: now). Dates, or relative: monday, next monday, tomorrow, lunedi..."
    option :template, type: :string, aliases: "-T",
           desc: "Slot template name from config (default: first template, usually work)"
    option :calendar, type: :string, aliases: "-c", desc: "Calendar name or ID"
    def slots
      apply_locale_override
      unless Auth.logged_in?
        puts Locale.t("errors.not_connected")
        exit 1
      end

      slot_cfg = Config.slots_config
      defaults = slot_cfg.fetch("defaults", {})
      in_value = options[:in].to_s.strip
      in_value = "1 week" if in_value.empty?

      duration_value = options[:duration].to_s.strip
      duration_value = defaults["default_duration"].to_s.strip if duration_value.empty?
      duration_value = "45min" if duration_value.empty?

      from_value = options[:from].to_s.strip
      from_value = defaults["from"].to_s.strip if from_value.empty?
      from_value = "now" if from_value.empty?

      begin
        template_name, template = resolve_slots_template(slot_cfg, options[:template])
        slot_duration = DurationParser.to_seconds(duration_value)
        free_before = DurationParser.to_seconds(slot_cfg["free_before"] || "0m")
        free_after = DurationParser.to_seconds(slot_cfg["free_after"] || "0m")
        time_min = parse_slots_from(from_value)
        time_max = DurationParser.add_to_time(in_value, time_min)
        hours = parse_workhours(template["hours"])
        days = parse_template_days(template["days"])
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

      calendars = service.list_calendars
      calendar_meta = exclude_calendar_ids.filter_map do |id|
        cal = calendars.find { |c| c.id == id }
        name = cal&.summary || id
        { id: id, name: name }
      end

      fetch_from = time_min - free_before
      events = exclude_calendar_ids.flat_map do |calendar_id|
        service.list_events(
          calendar_id,
          time_min: fetch_from,
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
        hours: hours,
        days: days,
        free_before_seconds: free_before,
        free_after_seconds: free_after
      )

      slots_by_day = finder.slots_by_day
      slot_count = slots_by_day.values.sum(&:size)
      puts SlotFormatter.format_header(
        from: time_min,
        to: time_max,
        duration: duration_value,
        calendars: calendar_meta,
        count: slot_count,
        template: template_name
      )
      puts ""
      output = SlotFormatter.format_output(slots_by_day)
      if output.empty?
        puts Locale.t("slots.no_available")
      else
        puts output
        copy_slots_to_clipboard(output)
      end
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

    def parse_slots_from(value)
      return Time.now if value.to_s.strip.downcase == "now"

      DateTimeParser.parse(value)
    end

    def resolve_slots_template(slot_cfg, requested_name)
      templates = slot_cfg["templates"]
      raise FlycalCli::Error, "slots.templates is missing in config.yml." unless templates.is_a?(Hash) && !templates.empty?

      name = requested_name.to_s.strip
      name = templates.keys.first.to_s if name.empty?

      template = templates[name]
      unless template.is_a?(Hash)
        available = templates.keys.join(", ")
        raise FlycalCli::Error, "Unknown slots template #{name.inspect}. Available: #{available}"
      end

      [name, template]
    end

    def parse_template_days(values)
      days = Array(values).map(&:to_i)
      raise FlycalCli::Error, "slots template days cannot be empty." if days.empty?

      invalid = days.reject { |d| d.between?(1, 7) }
      raise FlycalCli::Error, "Invalid template days #{invalid.inspect}. Use 1 (Mon) .. 7 (Sun)." unless invalid.empty?

      days.uniq
    end

    def copy_slots_to_clipboard(text)
      tool = Clipboard.copy(SlotFormatter.strip_ansi(text))
      return unless tool

      puts ""
      puts Locale.t("slots.copied_to_clipboard", tool: tool)
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
        raise FlycalCli::Error, "Invalid hours item #{item.inspect}. Use format like '9-13' or '14:30-18:00'." if start_str.nil? || end_str.nil?

        sh, sm = parse_hour_minute_flexible(start_str)
        eh, em = parse_hour_minute_flexible(end_str)
        start_minutes = (sh * 60) + sm
        end_minutes = (eh * 60) + em
        raise FlycalCli::Error, "Invalid hours range #{item.inspect}: end must be after start." if end_minutes <= start_minutes

        [sh, sm, eh, em]
      end

      raise FlycalCli::Error, "template hours cannot be empty in config.yml." if ranges.empty?

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
  end
end
