# frozen_string_literal: true

require "yaml"
require "fileutils"

module FlycalCli
  class Config
    CONFIG_DIR = File.expand_path("~/.flycal")
    CONFIG_FILE = File.join(CONFIG_DIR, "config.yml")
    CREDENTIALS_FILE = File.join(CONFIG_DIR, "credentials.json")
    TOKENS_FILE = File.join(CONFIG_DIR, "tokens.yml")

    class << self
      def load
        return {} unless File.exist?(CONFIG_FILE)

        YAML.load_file(CONFIG_FILE) || {}
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
    end
  end
end
