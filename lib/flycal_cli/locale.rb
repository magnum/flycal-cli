# frozen_string_literal: true

require "json"

module FlycalCli
  module Locale
    module_function

    FALLBACK_LOCALE = "en"

    def t(key, vars = {})
      value = lookup(translations(current_locale), key) || lookup(translations(FALLBACK_LOCALE), key) || key
      interpolate(value, vars)
    end

    def day_name(date_or_time)
      idx = date_or_time.to_date.wday
      days = t("common.weekdays.full")
      days[idx] || date_or_time.strftime("%A").downcase
    end

    def day_abbr(date_or_time)
      idx = date_or_time.to_date.wday
      days = t("common.weekdays.abbr")
      days[idx] || date_or_time.strftime("%a")
    end

    def month_name(date_or_time)
      idx = date_or_time.to_date.month - 1
      months = t("common.months.full")
      months[idx] || date_or_time.strftime("%B")
    end

    def current_locale
      Thread.current[:flycal_locale_override] || Config.locale
    rescue StandardError
      FALLBACK_LOCALE
    end

    def override!(locale)
      Thread.current[:flycal_locale_override] = locale.to_s if locale && !locale.to_s.strip.empty?
    end

    def translations(locale)
      @cache ||= {}
      loc = locale.to_s
      @cache[loc] ||= begin
        path = File.expand_path("../../locales/#{loc}.json", __dir__)
        File.exist?(path) ? JSON.parse(File.read(path)) : {}
      end
    end

    def lookup(hash, dotted_key)
      dotted_key.to_s.split(".").reduce(hash) do |acc, part|
        acc.is_a?(Hash) ? acc[part] : nil
      end
    end

    def interpolate(value, vars)
      return value unless value.is_a?(String)

      value.gsub(/%\{(\w+)\}/) do
        vars.fetch(Regexp.last_match(1).to_sym, Regexp.last_match(0)).to_s
      end
    end
  end
end
