# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlycalCli::Mock::CalendarService do
  subject(:service) { described_class.new(config) }

  let(:config) do
    mock_config(
      mockEventCount: 50,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-31",
      mockSeed: 42
    )
  end

  it "exposes a single calendar matching mockCalendar" do
    cals = service.list_calendars

    expect(cals.size).to eq(1)
    expect(cals.first.id).to eq("mock1")
    expect(cals.first.summary).to eq("mock1")
    expect(cals.first.primary).to eq(true)
  end

  it "filters by search timeframe" do
    all = service.list_all_events(
      ["mock1"],
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 31, 23, 59, 59)
    )
    narrow = service.list_all_events(
      ["mock1"],
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 3, 23, 59, 59)
    )

    expect(all.size).to eq(50)
    expect(narrow.size).to be < all.size
    expect(narrow.size).to be > 0
    narrow.each do |item|
      expect(item[:event].start.date_time).to be < Time.new(2026, 1, 3, 23, 59, 59)
      expect(item[:event].end.date_time).to be > Time.new(2026, 1, 1)
    end
  end

  it "filters by description contains (case-insensitive)" do
    work = service.list_all_events(
      ["mock1"],
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 31, 23, 59, 59),
      query: "work"
    )
    none = service.list_all_events(
      ["mock1"],
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 31, 23, 59, 59),
      query: "zzzz-not-present"
    )

    expect(work).not_to be_empty
    expect(work.map { |i| i[:event].summary }).to all(match(/work/i))
    expect(none).to be_empty
  end

  it "returns no events when calendar id does not match" do
    items = service.list_all_events(
      ["other"],
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 31, 23, 59, 59)
    )

    expect(items).to be_empty
  end

  it "returns empty when search window does not overlap mock generation window" do
    items = service.list_all_events(
      ["mock1"],
      time_min: Time.new(2026, 8, 21),
      time_max: Time.new(2026, 9, 20)
    )

    expect(items).to be_empty
  end
end
