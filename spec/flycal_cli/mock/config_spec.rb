# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe FlycalCli::Mock::Config do
  describe ".enabled?" do
    it "is true when mockTemplate is set" do
      expect(described_class.enabled?(mockTemplate: "mock1")).to eq(true)
    end

    it "is true when mockCalendar is set" do
      expect(described_class.enabled?(mockCalendar: "mock1")).to eq(true)
    end

    it "is false without mock flags" do
      expect(described_class.enabled?(description: "work")).to eq(false)
    end
  end

  describe ".from_options" do
    it "loads required fields from inline options" do
      cfg = mock_config(mockSeed: 7)

      expect(cfg.calendar_name).to eq("mock1")
      expect(cfg.seed).to eq(7)
      expect(cfg.patterns).to eq(%w[work personal event])
      expect(cfg.count).to eq(30)
      expect(cfg.duration_min_seconds).to eq(4 * 3600)
      expect(cfg.hours_from).to eq([9, 0])
      expect(cfg.hours_to).to eq([17, 0])
    end

    it "requires mockCalendar when not provided by template or CLI" do
      expect do
        described_class.from_options(
          mockEventDescriptionPatterns: "work",
          mockEventCount: 1,
          mockEventFrom: "2026-01-01",
          mockEventTo: "2026-01-02",
          mockEventDurationMin: "1h",
          mockEventDurationMax: "1h",
          mockEventHoursFrom: "09:00",
          mockEventHoursTo: "17:00"
        )
      end.to raise_error(FlycalCli::Error, /mockCalendar/)
    end

    it "loads a template from mockTemplates and lets CLI override values" do
      root = File.expand_path("../../..", __dir__)
      fixture = File.expand_path("../../fixtures/mockTemplates/fixture1.json", __dir__)
      dest = File.join(root, "mockTemplates", "fixture_spec_only.json")

      FileUtils.cp(fixture, dest)
      begin
        Dir.chdir(root) do
          cfg = described_class.from_options(
            mockTemplate: "fixture_spec_only",
            mockEventCount: 12
          )

          expect(cfg.calendar_name).to eq("fixture_cal")
          expect(cfg.count).to eq(12)
          expect(cfg.seed).to eq(99)
          expect(cfg.patterns).to eq(%w[alpha beta])
        end
      ensure
        FileUtils.rm_f(dest)
      end
    end

    it "rejects duration that does not fit the daily hours window" do
      expect do
        mock_config(
          mockEventDurationMin: "9h",
          mockEventDurationMax: "9h",
          mockEventHoursFrom: "09:00",
          mockEventHoursTo: "17:00"
        )
      end.to raise_error(FlycalCli::Error, /does not fit/)
    end
  end
end
