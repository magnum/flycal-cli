# frozen_string_literal: true

require "json"

module FlycalCli
  module Mock
    # Resolves mock options from CLI and/or a JSON template under mocks/.
    class Config
      TEMPLATE_KEYS = %w[
        mockCalendar
        mockEventDescriptionPatterns
        mockEventCount
        mockEventFrom
        mockEventTo
        mockEventDurationMin
        mockEventDurationMax
        mockEventHoursFrom
        mockEventHoursTo
        mockSeed
      ].freeze

      attr_reader :calendar_name, :seed, :patterns, :count,
                  :range_from, :range_to, :duration_min_seconds, :duration_max_seconds,
                  :hours_from, :hours_to, :template_name, :raw

      def self.enabled?(options)
        !options[:mockTemplate].to_s.empty? || !options[:mockCalendar].to_s.empty?
      end

      def self.from_options(options)
        new(options)
      end

      def initialize(options)
        merged = load_template(options[:mockTemplate])
        TEMPLATE_KEYS.each do |key|
          sym = key.to_sym
          value = options[sym]
          next if value.nil? || value.to_s.empty?

          merged[key] = value
        end

        @template_name = options[:mockTemplate].to_s.empty? ? nil : options[:mockTemplate].to_s
        calendar = merged["mockCalendar"].to_s
        calendar = options[:mockCalendar].to_s if calendar.empty?
        @calendar_name = calendar
        raise FlycalCli::Error,
              "Mock mode requires mockCalendar in the template (or --mockCalendar)." if @calendar_name.empty?

        @raw = merged
        @patterns = split_patterns(merged["mockEventDescriptionPatterns"])
        @count = Integer(merged["mockEventCount"])
        @range_from = parse_date(merged["mockEventFrom"], end_of_day: false)
        @range_to = parse_date(merged["mockEventTo"], end_of_day: true)
        @duration_min_seconds = DurationParser.to_seconds(merged["mockEventDurationMin"].to_s)
        @duration_max_seconds = DurationParser.to_seconds(merged["mockEventDurationMax"].to_s)
        @hours_from = parse_hour_minute(merged["mockEventHoursFrom"])
        @hours_to = parse_hour_minute(merged["mockEventHoursTo"])
        @seed = resolve_seed(merged["mockSeed"])

        validate!
      end

      def to_h
        {
          mock_calendar: calendar_name,
          mock_seed: seed,
          mock_template: template_name,
          mock_event_description_patterns: patterns.join(","),
          mock_event_count: count,
          mock_event_from: range_from,
          mock_event_to: range_to,
          mock_event_duration_min: duration_min_seconds,
          mock_event_duration_max: duration_max_seconds,
          mock_event_hours_from: hours_from,
          mock_event_hours_to: hours_to
        }
      end

      private

      def load_template(name)
        return {} if name.to_s.empty?

        path = find_template_path(name)
        raise FlycalCli::Error, "Mock template not found: #{name.inspect} (looked in ./mocks, ./mockTemplates, and gem paths)." unless path

        data = JSON.parse(File.read(path))
        raise FlycalCli::Error, "Mock template #{name.inspect} must be a JSON object." unless data.is_a?(Hash)

        data
      rescue JSON::ParserError => e
        raise FlycalCli::Error, "Invalid mock template JSON (#{name}): #{e.message}"
      end

      def find_template_path(name)
        base = name.to_s.sub(/\.json\z/, "")
        gem_root = File.expand_path("../../..", __dir__)
        candidates = [
          File.join(Dir.pwd, "mocks", "#{base}.json"),
          File.join(Dir.pwd, "mockTemplates", "#{base}.json"),
          File.join(gem_root, "mocks", "#{base}.json"),
          File.join(gem_root, "mockTemplates", "#{base}.json")
        ]
        candidates.find { |p| File.file?(p) }
      end

      def split_patterns(value)
        list = value.to_s.split(",").map(&:strip).reject(&:empty?)
        raise FlycalCli::Error, "mockEventDescriptionPatterns must list at least one pattern." if list.empty?

        list
      end

      def parse_date(value, end_of_day:)
        raise FlycalCli::Error, "Missing mock date." if value.to_s.empty?

        DateTimeParser.parse(value.to_s, end_of_day: end_of_day)
      end

      def parse_hour_minute(value)
        str = value.to_s.strip
        match = str.match(/\A(\d{1,2}):(\d{2})\z/)
        raise FlycalCli::Error, "Invalid mock hour #{value.inspect}. Use HH:MM (e.g. 09:00)." unless match

        hour = match[1].to_i
        min = match[2].to_i
        unless hour.between?(0, 23) && min.between?(0, 59)
          raise FlycalCli::Error, "Invalid mock hour #{value.inspect}. Use HH:MM (e.g. 09:00)."
        end

        [hour, min]
      end

      def resolve_seed(value)
        return Integer(value) unless value.nil? || value.to_s.empty?

        Random.new_seed & 0xFFFFFFFF
      end

      def validate!
        missing = []
        missing << "mockEventDescriptionPatterns" if patterns.empty?
        missing << "mockEventCount" if count <= 0
        missing << "mockEventFrom" if range_from.nil?
        missing << "mockEventTo" if range_to.nil?
        missing << "mockEventDurationMin" if duration_min_seconds <= 0
        missing << "mockEventDurationMax" if duration_max_seconds <= 0
        raise FlycalCli::Error, "Missing mock parameters: #{missing.join(", ")}" unless missing.empty?

        if duration_min_seconds > duration_max_seconds
          raise FlycalCli::Error, "mockEventDurationMin must be <= mockEventDurationMax."
        end
        if range_from > range_to
          raise FlycalCli::Error, "mockEventFrom must be before mockEventTo."
        end

        from_mins = hours_from[0] * 60 + hours_from[1]
        to_mins = hours_to[0] * 60 + hours_to[1]
        if from_mins >= to_mins
          raise FlycalCli::Error, "mockEventHoursFrom must be before mockEventHoursTo."
        end
        if duration_min_seconds > (to_mins - from_mins) * 60
          raise FlycalCli::Error,
                "mockEventDurationMin does not fit in mockEventHoursFrom..mockEventHoursTo window."
        end
      end
    end
  end
end
