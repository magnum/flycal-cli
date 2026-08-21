# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Search pipeline with JsonRenderer and mock calendar" do
  def parse_json(output)
    JSON.parse(output)
  end

  it "returns valid pretty JSON with params, info, items, and groups" do
    config = mock_config(
      mockEventCount: 12,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-05",
      mockEventDurationMin: "4h",
      mockEventDurationMax: "4h",
      mockSeed: 42
    )
    _params, output = run_search_pipeline(
      config: config,
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 5, 23, 59, 59),
      format: "json"
    )

    expect(output).to include("\n  ") # pretty-printed
    data = parse_json(output)

    expect(data.keys).to contain_exactly("params", "info", "items", "groups")
    expect(data["params"]["command"]).to eq("search")
    expect(data["params"]["format"]).to eq("json")
    expect(data["params"]["group_by"]).to eq("day")
    expect(data["params"]["from"]).to include("2026-01-01")
    expect(data["params"]["to"]).to include("2026-01-05")
    expect(data["params"]["use_mock"]).to eq(true)
    expect(data["params"]["mock_seed"]).to eq(42)

    expect(data["info"]["events_found"]).to eq(12)
    expect(data["info"]["total_hours"]).to eq(48.0)
    expect(data["info"]["total_working_days"]).to eq(6.0)
    expect(data["info"]["mock_seed"]).to eq(42)

    expect(data["items"].size).to eq(12)
    expect(data["items"].first).to include(
      "summary" => a_kind_of(String),
      "start" => a_hash_including("dateTime" => a_kind_of(String)),
      "end" => a_hash_including("dateTime" => a_kind_of(String)),
      "calendarId" => "mock1",
      "calendarSummary" => "mock1"
    )

    expect(data["groups"]).not_to be_empty
    expect(data["groups"]).to all(include("type" => "day", "items" => a_kind_of(Array)))
    expect(data["groups"].sum { |g| g["items"].size }).to eq(12)
  end

  it "filters items by description and keeps group items consistent" do
    config = mock_config(
      mockEventCount: 40,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-31",
      mockSeed: 7
    )
    _params, output = run_search_pipeline(
      config: config,
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 31, 23, 59, 59),
      description: "work",
      format: "json"
    )
    data = parse_json(output)

    expect(data["items"]).not_to be_empty
    expect(data["items"].map { |e| e["summary"] }).to all(match(/work/i))
    expect(data["info"]["events_found"]).to eq(data["items"].size)
    data["groups"].each do |group|
      expect(group["items"].map { |e| e["summary"] }).to all(match(/work/i))
    end
  end

  it "uses week groups for mid-length timeframes" do
    config = mock_config(
      mockEventCount: 30,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-20",
      mockSeed: 3
    )
    _params, output = run_search_pipeline(
      config: config,
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 20, 23, 59, 59),
      format: "json"
    )
    data = parse_json(output)

    expect(data["params"]["group_by"]).to eq("week")
    expect(data["groups"]).to all(include("type" => "week"))
    expect(data["groups"].size).to be > 1
  end

  it "uses month groups for long timeframes" do
    config = mock_config(
      mockEventCount: 50,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-03-15",
      mockSeed: 9
    )
    _params, output = run_search_pipeline(
      config: config,
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 3, 15, 23, 59, 59),
      format: "json"
    )
    data = parse_json(output)

    expect(data["params"]["group_by"]).to eq("month")
    expect(data["groups"]).to all(include("type" => "month"))
    expect(data["groups"].map { |g| g["key"] }).to include("2026-01", "2026-02", "2026-03")
  end

  it "is reproducible for the same mock seed" do
    build = lambda do
      config = mock_config(mockEventCount: 10, mockSeed: 55, mockEventTo: "2026-01-10")
      _p, out = run_search_pipeline(
        config: config,
        time_min: Time.new(2026, 1, 1),
        time_max: Time.new(2026, 1, 10, 23, 59, 59),
        format: "json"
      )
      out
    end

    expect(build.call).to eq(build.call)
  end
end
