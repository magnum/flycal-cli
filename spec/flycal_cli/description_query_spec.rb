# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlycalCli::DescriptionQuery do
  describe ".patterns" do
    it "splits on pipe and comma" do
      expect(described_class.patterns("rui|solver")).to eq(%w[rui solver])
      expect(described_class.patterns("rui, solver")).to eq(%w[rui solver])
      expect(described_class.patterns("  a | b , c ")).to eq(%w[a b c])
    end
  end

  describe ".match?" do
    it "matches any OR term case-insensitively on summary or description" do
      expect(described_class.match?("Meeting Rui", nil, "rui|solver")).to eq(true)
      expect(described_class.match?(nil, "SOLVER sync", "rui|solver")).to eq(true)
      expect(described_class.match?("other", "none", "rui|solver")).to eq(false)
    end
  end
end
