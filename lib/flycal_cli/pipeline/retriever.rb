# frozen_string_literal: true

module FlycalCli
  module Pipeline
    # First pipeline layer: fetch calendar events for the requested timeframe.
    class Retriever
      def initialize(calendar_service)
        @service = calendar_service
      end

      # Expects params: :calendar_ids, :time_min, :time_max, optional :description
      # Writes: :events (normalized), :calendar_names
      def call(params)
        calendar_ids = Array(params[:calendar_ids])
        time_min = params[:time_min]
        time_max = params[:time_max]
        query = params[:description]

        calendar_list = @service.list_calendars
        calendar_names = calendar_list.to_h { |c| [c.id, c.summary || c.id] }
        params[:calendar_names] = calendar_names

        raw = @service.list_all_events(
          calendar_ids,
          time_min: time_min,
          time_max: time_max,
          query: query
        )

        params[:events] = raw.map { |item| normalize_event(item, calendar_names) }
        params
      end

      private

      def normalize_event(item, calendar_names)
        event = item[:event]
        cal_id = item[:calendar_id]
        start_at = to_time(event.start&.date_time || event.start&.date)
        end_at = to_time(event.end&.date_time || event.end&.date)
        minutes =
          if start_at && end_at && end_at > start_at
            (end_at - start_at) / 60.0
          else
            0.0
          end

        {
          calendar_id: cal_id,
          calendar_name: calendar_names[cal_id] || cal_id,
          summary: event.summary,
          description: event.description,
          start_at: start_at,
          end_at: end_at,
          duration_minutes: minutes,
          all_day: !event.start&.date.nil? && event.start&.date_time.nil?,
          raw: event
        }
      end

      def to_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        return value.to_time if value.respond_to?(:to_time) && !value.is_a?(String)

        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
