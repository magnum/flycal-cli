# frozen_string_literal: true

require "json"

module FlycalCli
  module Pipeline
    # Pretty-printed JSON output for search (API / tooling friendly).
    class JsonRenderer < Renderer
      def render(params)
        payload = {
          "params" => build_params(params),
          "info" => build_info(params),
          "items" => Array(params[:events]).map { |ev| serialize_event(ev) },
          "groups" => build_groups(params)
        }

        JSON.pretty_generate(payload) + "\n"
      end

      private

      def build_params(params)
        out = {
          "command" => params[:command] || "search",
          "from" => format_time(params[:time_min]),
          "to" => format_time(params[:time_max]),
          "calendar" => params[:calendar],
          "calendar_ids" => Array(params[:calendar_ids]),
          "description" => params[:description],
          "format" => params[:format] || "json",
          "locale" => params[:locale] || Locale.current_locale,
          "group_by" => params[:group_by],
          "group_by_option" => blank_to_nil(params[:group_by_option]),
          "from_option" => blank_to_nil(params[:from_option]),
          "to_option" => blank_to_nil(params[:to_option]),
          "in_option" => blank_to_nil(params[:in_option])
        }

        if params[:use_mock]
          out["use_mock"] = true
          out["mock_calendar"] = params[:mock_calendar]
          out["mock_template"] = params[:mock_template]
          out["mock_seed"] = params[:mock_seed]
        end

        out
      end

      def build_info(params)
        totals = params[:totals] || {}
        total_minutes = totals[:total_minutes].to_f
        info = {
          "events_found" => totals[:event_count].to_i,
          "from" => format_time(params[:time_min]),
          "to" => format_time(params[:time_max]),
          "total_hours" => (total_minutes / 60.0).round(2),
          "total_working_days" => totals[:working_days].to_f
        }
        info["mock_seed"] = params[:mock_seed] if params[:use_mock] && !params[:mock_seed].nil?
        info
      end

      def build_groups(params)
        type = params[:group_by].to_s
        Array(params[:groups]).map do |group|
          {
            "type" => type,
            "key" => group[:key],
            "index" => group[:index],
            "total_hours" => group[:hours],
            "total_working_days" => group[:working_days],
            "events_found" => group[:event_count] || Array(group[:events]).size,
            "items" => Array(group[:events]).map { |ev| serialize_event(ev) }
          }.tap do |g|
            if type == "string"
              g["string"] = group[:string] || group[:key]
            else
              g["from"] = format_time(group[:start_at])
              g["to"] = format_time(group[:end_at])
            end
            g["month_name"] = group[:month_name] if group[:month_name]
          end
        end
      end

      # Shape inspired by Google Calendar API event resources.
      def serialize_event(ev)
        raw = ev[:raw]
        payload = {
          "summary" => ev[:summary],
          "description" => ev[:description],
          "start" => boundary_hash(ev[:start_at], all_day: ev[:all_day]),
          "end" => boundary_hash(ev[:end_at], all_day: ev[:all_day]),
          "calendarId" => ev[:calendar_id],
          "calendarSummary" => ev[:calendar_name]
        }

        if raw
          payload["id"] = raw.id if raw.respond_to?(:id) && raw.id
          payload["status"] = raw.status if raw.respond_to?(:status) && raw.status
          payload["htmlLink"] = raw.html_link if raw.respond_to?(:html_link) && raw.html_link
          payload["created"] = format_time(raw.created) if raw.respond_to?(:created) && raw.created
          payload["updated"] = format_time(raw.updated) if raw.respond_to?(:updated) && raw.updated
          payload["location"] = raw.location if raw.respond_to?(:location) && raw.location
          payload["iCalUID"] = raw.i_cal_uid if raw.respond_to?(:i_cal_uid) && raw.i_cal_uid
        end

        payload.compact
      end

      def boundary_hash(time, all_day:)
        return nil if time.nil?

        if all_day
          { "date" => time.to_date.iso8601 }
        else
          { "dateTime" => format_time(time) }
        end
      end

      # Google Calendar-style ISO-8601 datetime, e.g. 2026-07-29T14:41:00+00:00
      def format_time(value)
        return nil if value.nil?
        return value.iso8601 if value.respond_to?(:iso8601)

        value.to_s
      end

      def blank_to_nil(value)
        str = value.to_s
        str.empty? ? nil : str
      end
    end
  end
end
