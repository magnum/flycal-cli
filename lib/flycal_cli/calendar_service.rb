# frozen_string_literal: true

require "google/apis/calendar_v3"

module FlycalCli
  class CalendarService
    def initialize(credentials)
      @service = Google::Apis::CalendarV3::CalendarService.new
      @service.authorization = credentials
    end

    def list_calendars
      result = @service.list_calendar_lists
      result.items || []
    end

    def get_calendar(calendar_id)
      @service.get_calendar(calendar_id)
    end

    def list_events(calendar_id, time_min:, time_max:, query: nil)
      events = []
      page_token = nil

      loop do
        result = @service.list_events(
          calendar_id,
          time_min: time_min.iso8601,
          time_max: time_max.iso8601,
          q: query,
          single_events: true,
          order_by: "startTime",
          page_token: page_token
        )

        events.concat(result.items || [])

        page_token = result.next_page_token
        break if page_token.nil? || page_token.empty?
      end

      events
    end

    def list_all_events(calendar_ids, time_min:, time_max:, query: nil)
      all_events = []

      # When --description is used: fetch all events and filter client-side to guarantee
      # contains/like behavior. We do not use the API's q param so we can ensure we
      # return all events where the string appears in summary or description (case-insensitive).
      calendar_ids.each do |cal_id|
        begin
          events = list_events(cal_id, time_min: time_min, time_max: time_max, query: nil)
          events.each { |e| all_events << { calendar_id: cal_id, event: e } }
        rescue Google::Apis::Errors::Error => e
          warn "Error in calendar #{cal_id}: #{e.message}"
        end
      end

      # Filter: summary/description contains any OR term from query ("a|b"), case-insensitive.
      if query && !query.to_s.strip.empty?
        all_events.select! do |item|
          event = item[:event]
          DescriptionQuery.match?(event.summary, event.description, query)
        end
      end

      all_events
    end
  end
end
