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

  it "treats non day/week/month groupBy values as string patterns" do
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
      description: nil,
      group_by: "work|personal",
      format: "json"
    )
    data = JSON.parse(output)

    expect(params[:group_by]).to eq("string")
    expect(data["params"]["group_by"]).to eq("string")
    expect(data["params"]["group_by_option"]).to eq("work|personal")
    expect(data["groups"].size).to eq(2)
    expect(data["groups"].map { |g| g["string"] }).to eq(%w[work personal])
    expect(data["groups"]).to all(include("type" => "string"))
    data["groups"].each do |group|
      expect(group).not_to have_key("from")
      expect(group).not_to have_key("to")
      expect(group).not_to have_key("description")
      expect(group["items"]).to all(satisfy { |ev| ev["summary"].downcase.include?(group["string"]) })
    end
  end

  it "keeps --description filter independent from --groupBy string" do
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
      description: "work",
      group_by: "work|personal",
      format: "json"
    )
    data = JSON.parse(output)

    expect(data["items"].map { |e| e["summary"] }).to all(match(/work/i))
    personal_group = data["groups"].find { |g| g["string"] == "personal" }
    expect(personal_group["items"]).to be_empty
    work_group = data["groups"].find { |g| g["string"] == "work" }
    expect(work_group["items"]).not_to be_empty
    expect(params[:group_by]).to eq("string")
  end

  it "formats day/week/month group from/to as Google ISO-8601 without string key" do
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

    expect(group["from"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    expect(group["to"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    expect(group).not_to have_key("string")
  end

  it "resolves unknown groupBy shortcuts as string mode" do
    expect(FlycalCli::Pipeline::Aggregator.resolve_group_by(10, "rui|solver")).to eq("string")
    expect(FlycalCli::Pipeline::Aggregator.resolve_group_by(40, "day")).to eq("day")
    expect(FlycalCli::Pipeline::Aggregator.resolve_group_by(40, nil)).to eq("month")
  end
end
