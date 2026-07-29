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
        save(merged) if changed || !File.exist?(CONFIG_FILE)

        merged
      end

      def save(data)
        FileUtils.mkdir_p(CONFIG_DIR)
        File.write(CONFIG_FILE, data.to_yaml)
      end

      def calendar_default
        load["calendar_default"]
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
