# frozen_string_literal: true

require "flycal_cli"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.order = :random
  Kernel.srand config.seed

  config.before do
    FlycalCli::Locale.override!("en")
  end
end

module FlycalSpecHelpers
  module_function

  def strip_ansi(text)
    text.to_s.gsub(/\e\[[0-9;]*m/, "")
  end

  def default_mock_options(overrides = {})
    {
      mockCalendar: "mock1",
      mockEventDescriptionPatterns: "work,personal,event",
      mockEventCount: 30,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-31",
      mockEventDurationMin: "4h",
      mockEventDurationMax: "4h",
      mockEventHoursFrom: "09:00",
      mockEventHoursTo: "17:00",
      mockSeed: 42
    }.merge(overrides)
  end

  def mock_config(overrides = {})
    FlycalCli::Mock::Config.from_options(default_mock_options(overrides))
  end

  def run_search_pipeline(config:, time_min:, time_max:, description: nil, calendar_ids: nil)
    service = FlycalCli::Mock::CalendarService.new(config)
    params = FlycalCli::Pipeline::Params.new(
      time_min: time_min,
      time_max: time_max,
      calendar_ids: calendar_ids || [config.calendar_name],
      description: description,
      format: "text",
      use_mock: true,
      mock_seed: config.seed,
      mock_calendar: config.calendar_name
    )
    output = FlycalCli::Pipeline::SearchPipeline.new(service).run(params)
    [params, output]
  end
end

RSpec.configure do |config|
  config.include FlycalSpecHelpers
  config.extend FlycalSpecHelpers
end
