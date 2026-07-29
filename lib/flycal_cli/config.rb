# frozen_string_literal: true

require "yaml"
require "fileutils"

module FlycalCli
  class Config
    CONFIG_DIR = File.expand_path("~/.flycal")
    CONFIG_FILE = File.join(CONFIG_DIR, "config.yml")
    CREDENTIALS_FILE = File.join(CONFIG_DIR, "credentials.json")
    TOKENS_FILE = File.join(CONFIG_DIR, "tokens.yml")
    DEFAULTS_FILE = File.expand_path("../../config/defaults.yml", __dir__)

    class << self
      def load
        user_data = if File.exist?(CONFIG_FILE)
                      YAML.load_file(CONFIG_FILE) || {}
                    else
                      {}
                    end

        merged, changed = merge_missing_defaults(user_data, default_values)
        merged, migrated = normalize_slots_keys(merged)
        save(merged) if changed || migrated || !File.exist?(CONFIG_FILE)

        merged
      end

      def save(data)
        FileUtils.mkdir_p(CONFIG_DIR)
        File.write(CONFIG_FILE, data.to_yaml)
      end

      def calendar_default
        value = load["calendar_default"]
        return nil if value.nil? || value.to_s.strip.empty? || value.to_s == "~"

        value.to_s
      end

      def calendar_default=(calendar_id)
        data = load
        data["calendar_default"] = calendar_id
        save(data)
      end

      def credentials_path
        CREDENTIALS_FILE
      end

      def credentials_exist?
        File.exist?(CREDENTIALS_FILE)
      end

      def tokens_path
        TOKENS_FILE
      end

      def config_dir
        CONFIG_DIR
      end

      def clear_all
        FileUtils.rm_rf(CONFIG_DIR)
      end

      def slots_config
        load.fetch("slots", {})
      end

      def exclude_calendars
        Array(slots_config["exclude_calendars"]).map(&:to_s).reject(&:empty?)
      end

      def exclude_calendars=(calendar_ids)
        data = load
        data["slots"] ||= {}
        data["slots"]["exclude_calendars"] = Array(calendar_ids).map(&:to_s)
        save(data)
      end

      def normalize_slots_keys(data)
        slots = data["slots"]
        return [data, false] unless slots.is_a?(Hash)

        changed = false
        normalized = slots.dup

        if normalized.key?("exclude-calendars") && !normalized.key?("exclude_calendars")
          normalized["exclude_calendars"] = normalized.delete("exclude-calendars")
          changed = true
        end

        if normalized.key?("weekdays-only") && !normalized.key?("weekdays_only")
          normalized["weekdays_only"] = normalized.delete("weekdays-only")
          changed = true
        end

        if normalized.key?("workhours") && !normalized.key?("hours")
          normalized["hours"] = normalized.delete("workhours")
          changed = true
        end

        if normalized.key?("tempaltes") && !normalized.key?("templates")
          normalized["templates"] = normalized.delete("tempaltes")
          changed = true
        end

        templates = normalized["templates"]
        templates_empty = !templates.is_a?(Hash) || templates.empty?

        if templates_empty && normalized["hours"]
          days =
            if normalized.key?("weekdays_only") && normalized["weekdays_only"] == false
              [1, 2, 3, 4, 5, 6, 7]
            else
              [1, 2, 3, 4, 5]
            end

          normalized["templates"] = {
            "work" => {
              "days" => days,
              "hours" => deep_dup(normalized["hours"])
            }
          }
          changed = true
        end

        %w[hours weekdays_only weekdays-only workhours tempaltes].each do |legacy_key|
          next unless normalized.key?(legacy_key)

          normalized.delete(legacy_key)
          changed = true
        end

        return [data, false] unless changed

        data = data.dup
        data["slots"] = normalized
        [data, true]
      end

      def config_file
        CONFIG_FILE
      end

      def locale
        load["locale"].to_s
      end

      def locale=(value)
        data = load
        data["locale"] = value.to_s
        save(data)
      end

      def default_values
        @default_values ||= begin
          raise "Defaults file not found: #{DEFAULTS_FILE}" unless File.exist?(DEFAULTS_FILE)

          YAML.load_file(DEFAULTS_FILE) || {}
        end
      end

      def merge_missing_defaults(target, defaults)
        merged = target.dup
        changed = false

        defaults.each do |key, default_value|
          if !merged.key?(key)
            merged[key] = deep_dup(default_value)
            changed = true
          elsif default_value.is_a?(Hash) && merged[key].is_a?(Hash)
            nested, nested_changed = merge_missing_defaults(merged[key], default_value)
            merged[key] = nested
            changed ||= nested_changed
          end
        end

        [merged, changed]
      end

      def deep_dup(value)
        case value
        when Hash
          value.transform_values { |v| deep_dup(v) }
        when Array
          value.map { |v| deep_dup(v) }
        else
          value
        end
      end

      private :default_values, :merge_missing_defaults, :deep_dup
    end
  end
end
