# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlycalCli::Mock::EventGenerator do
  def generate(overrides = {})
    described_class.new(mock_config(overrides)).generate
  end

  it "generates exactly mockEventCount events" do
    events = generate(mockEventCount: 17)

    expect(events.size).to eq(17)
  end

  it "builds titles from patterns with per-pattern indexes" do
    events = generate(
      mockEventCount: 9,
      mockEventDescriptionPatterns: "work,personal,event",
      mockSeed: 11
    )
    titles = events.map(&:summary)

    expect(titles).to all(match(/\A(work|personal|event)\d+\z/))
    %w[work personal event].each do |pattern|
      numbered = titles.grep(/\A#{pattern}\d+\z/)
      indexes = numbered.map { |t| t.delete_prefix(pattern).to_i }.sort
      expect(indexes).to eq((1..numbered.size).to_a)
    end
  end

  it "keeps every event inside the mock date range and daily hours window" do
    events = generate(
      mockEventCount: 40,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-10",
      mockEventDurationMin: "4h",
      mockEventDurationMax: "4h",
      mockEventHoursFrom: "09:00",
      mockEventHoursTo: "17:00",
      mockSeed: 5
    )

    events.each do |event|
      start_at = event.start.date_time
      end_at = event.end.date_time

      expect(start_at.to_date).to be_between(Date.new(2026, 1, 1), Date.new(2026, 1, 10))
      expect(end_at - start_at).to eq(4 * 3600)
      expect(start_at.hour * 60 + start_at.min).to be >= (9 * 60)
      expect(end_at.hour * 60 + end_at.min).to be <= (17 * 60)
    end
  end

  it "is reproducible for the same seed and differs for another seed" do
    a = generate(mockSeed: 123, mockEventCount: 20).map { |e| [e.summary, e.start.date_time] }
    b = generate(mockSeed: 123, mockEventCount: 20).map { |e| [e.summary, e.start.date_time] }
    c = generate(mockSeed: 456, mockEventCount: 20).map { |e| [e.summary, e.start.date_time] }

    expect(a).to eq(b)
    expect(a).not_to eq(c)
  end

  it "returns events sorted by start time" do
    starts = generate(mockEventCount: 25, mockSeed: 3).map { |e| e.start.date_time }

    expect(starts).to eq(starts.sort)
  end
end
