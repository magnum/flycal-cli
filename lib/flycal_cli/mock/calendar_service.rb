# frozen_string_literal: true

module FlycalCli
  module Mock
    # Duck-typed CalendarService backed by generated mock events (no Google API).
    class CalendarService
      Calendar = Struct.new(:id, :summary, :primary, keyword_init: true)

      def initialize(config)
        @config = config
        @calendar_id = config.calendar_name
        @events = EventGenerator.new(config).generate
      end

      def list_calendars
        [Calendar.new(id: @calendar_id, summary: @calendar_id, primary: true)]
      end

      def list_all_events(calendar_ids, time_min:, time_max:, query: nil)
        ids = Array(calendar_ids)
        return [] unless ids.empty? || ids.include?(@calendar_id)

        items = @events.filter_map do |event|
          start_at = event.start.date_time
          end_at = event.end.date_time
          next if start_at.nil? || end_at.nil?
          next if end_at <= time_min || start_at >= time_max

          { calendar_id: @calendar_id, event: event }
        end

        if query && !query.to_s.strip.empty?
          items.select! do |item|
            event = item[:event]
            DescriptionQuery.match?(event.summary, event.description, query)
          end
        end

        items
      end
    end
  end
end
