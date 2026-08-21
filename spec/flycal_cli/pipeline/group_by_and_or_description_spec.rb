# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "OR description filter and groupBy overrides" do
  it "matches description OR terms with pipe" do
    config = mock_config(
      mockEventCount: 60,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-31",
      mockEventDescriptionPatterns: "work,personal,event",
      mockSeed: 11
    )
    service = FlycalCli::Mock::CalendarService.new(config)
    work = service.list_all_events(
      ["mock1"],
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 31, 23, 59, 59),
      query: "work"
    )
    personal = service.list_all_events(
      ["mock1"],
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 31, 23, 59, 59),
      query: "personal"
    )
    either = service.list_all_events(
      ["mock1"],
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 31, 23, 59, 59),
      query: "work|personal"
    )

    expect(either.size).to eq(work.size + personal.size)
    expect(either.map { |i| i[:event].summary }).to all(match(/work|personal/i))
  end

  it "overrides auto month grouping when --groupBy day is set" do
    config = mock_config(
      mockEventCount: 20,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-03-15",
      mockSeed: 4
    )
    params, = run_search_pipeline(
      config: config,
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 3, 15, 23, 59, 59),
      group_by: "day",
      format: "json"
    )

    expect(params[:group_by]).to eq("day")
    expect(params[:groups].first[:key]).to match(/\A2026-01-01\z/)
  end

  it "groups by description terms from --description" do
    config = mock_config(
      mockEventCount: 45,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-31",
      mockEventDescriptionPatterns: "work,personal,event",
      mockSeed: 8
    )
    params, output = run_search_pipeline(
      config: config,
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 31, 23, 59, 59),
      description: "work|personal",
      group_by: "description",
      format: "json"
    )
    data = JSON.parse(output)

    expect(params[:group_by]).to eq("description")
    expect(data["groups"].size).to eq(2)
    expect(data["groups"].map { |g| g["description"] }).to eq(%w[work personal])
    expect(data["groups"]).to all(include("type" => "description"))
    data["groups"].each do |group|
      expect(group).not_to have_key("from")
      expect(group).not_to have_key("to")
      expect(group["items"]).to all(satisfy { |ev| ev["summary"].downcase.include?(group["description"]) })
    end
  end

  it "formats day/week/month group from/to as YYYYMMDDTHHMMSS without description key" do
    config = mock_config(
      mockEventCount: 10,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-20",
      mockSeed: 2
    )
    _params, output = run_search_pipeline(
      config: config,
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 20, 23, 59, 59),
      group_by: "week",
      format: "json"
    )
    data = JSON.parse(output)
    group = data["groups"].first

    expect(group["from"]).to match(/\A\d{8}T\d{6}\z/)
    expect(group["to"]).to match(/\A\d{8}T\d{6}\z/)
    expect(group).not_to have_key("description")
  end

  it "rejects invalid groupBy values" do
    expect do
      FlycalCli::Pipeline::Aggregator.resolve_group_by(10, "hours")
    end.to raise_error(FlycalCli::Error, /Unsupported groupBy/)
  end
end
