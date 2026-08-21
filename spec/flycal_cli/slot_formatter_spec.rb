# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe FlycalCli::SlotFormatter do
  describe ".format_json" do
    let(:day) { Date.new(2026, 3, 2) } # Monday
    let(:start_at) { Time.new(2026, 3, 2, 9, 0, 0) }
    let(:end_at) { Time.new(2026, 3, 2, 12, 0, 0) }
    let(:slots_by_day) { { day => [[start_at, end_at]] } }

    it "returns valid pretty JSON with params, info, items, and day groups" do
      output = described_class.format_json(
        slots_by_day: slots_by_day,
        time_min: Time.new(2026, 3, 2, 0, 0, 0),
        time_max: Time.new(2026, 3, 6, 23, 59, 59),
        duration: "45min",
        template: "work",
        calendars: [{ id: "cal-1", name: "Work" }],
        locale: "en",
        from_option: "2026-03-02",
        in_option: "5 days",
        free_before: "15min",
        free_after: "15min"
      )

      expect(output).to include("\n  ")
      data = JSON.parse(output)

      expect(data.keys).to contain_exactly("params", "info", "items", "groups")
      expect(data["params"]["command"]).to eq("slots")
      expect(data["params"]["format"]).to eq("json")
      expect(data["params"]["template"]).to eq("work")
      expect(data["params"]["duration"]).to eq("45min")
      expect(data["params"]["calendar_ids"]).to eq(["cal-1"])

      expect(data["info"]["slots_found"]).to eq(1)
      expect(data["info"]["template"]).to eq("work")
      expect(data["info"]["calendars"]).to eq([{ "id" => "cal-1", "name" => "Work" }])
      expect(data["info"]["link"]).to include("calendar.google.com")
      expect(data["info"]["from"]).to match(/\A\d{4}-\d{2}-\d{2}T/)

      expect(data["items"].size).to eq(1)
      expect(data["items"].first).to include(
        "date" => "2026-03-02",
        "start" => a_hash_including("dateTime" => a_string_matching(/\A2026-03-02T09:00:00/)),
        "end" => a_hash_including("dateTime" => a_string_matching(/\A2026-03-02T12:00:00/)),
        "duration_seconds" => 3 * 3600
      )

      expect(data["groups"].size).to eq(1)
      expect(data["groups"].first).to include(
        "type" => "day",
        "key" => "2026-03-02",
        "slots_found" => 1
      )
      expect(data["groups"].first["items"]).to eq(data["items"])
    end

    it "returns empty items/groups when there are no slots" do
      output = described_class.format_json(
        slots_by_day: {},
        time_min: Time.new(2026, 3, 2),
        time_max: Time.new(2026, 3, 3),
        duration: "1h",
        template: "work",
        calendars: []
      )
      data = JSON.parse(output)

      expect(data["info"]["slots_found"]).to eq(0)
      expect(data["items"]).to eq([])
      expect(data["groups"]).to eq([])
    end
  end
end
