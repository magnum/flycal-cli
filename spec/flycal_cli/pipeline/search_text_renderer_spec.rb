# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Search pipeline with TextRenderer and mock calendar" do
  def plain(output)
    strip_ansi(output)
  end

  it "renders event lines, summary, and mock seed for overlapping search window" do
    config = mock_config(
      mockEventCount: 20,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-07",
      mockEventDurationMin: "4h",
      mockEventDurationMax: "4h",
      mockSeed: 42
    )
    time_min = Time.new(2026, 1, 1, 0, 0, 0)
    time_max = Time.new(2026, 1, 7, 23, 59, 59)

    params, output = run_search_pipeline(
      config: config,
      time_min: time_min,
      time_max: time_max,
      description: nil
    )
    text = plain(output)

    expect(params[:events].size).to eq(20)
    expect(params[:group_by]).to eq("day")
    expect(text).to include("mock1 |")
    expect(text).to match(/Events found: 20/)
    expect(text).to include("Mock seed: 42")
    expect(text).to include("From: Thu 2026-01-01 00:00 | To: Wed 2026-01-07 23:59")
    expect(text).to include("Total time occupied:")
    expect(text).not_to include("By week:")
    expect(text).not_to include("By month:")

    event_lines = text.lines.select { |l| l.include?(" | ") && l.start_with?("mock1") }
    expect(event_lines.size).to eq(20)
    expect(event_lines.first).to match(/\Amock1 \| \w{3} 2026-01-\d{2} \d{2}:\d{2} \| \w{3} 2026-01-\d{2} \d{2}:\d{2} \| /)
  end

  it "filters events by description and updates totals accordingly" do
    config = mock_config(
      mockEventCount: 60,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-31",
      mockSeed: 7
    )
    time_min = Time.new(2026, 1, 1)
    time_max = Time.new(2026, 1, 31, 23, 59, 59)

    _all_params, all_out = run_search_pipeline(
      config: config,
      time_min: time_min,
      time_max: time_max
    )
    work_params, work_out = run_search_pipeline(
      config: config,
      time_min: time_min,
      time_max: time_max,
      description: "work"
    )

    all_count = plain(all_out)[/Events found: (\d+)/, 1].to_i
    work_count = plain(work_out)[/Events found: (\d+)/, 1].to_i

    expect(all_count).to eq(60)
    expect(work_count).to be_between(1, all_count - 1)
    expect(work_params[:events].map { |e| e[:summary] }).to all(match(/work/i))
    expect(plain(work_out)).to include("Mock seed: 7")
  end

  it "shows weekly breakdown for search windows longer than 7 days" do
    config = mock_config(
      mockEventCount: 40,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-20",
      mockSeed: 3
    )
    params, output = run_search_pipeline(
      config: config,
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 20, 23, 59, 59)
    )
    text = plain(output)

    expect(params[:group_by]).to eq("week")
    expect(text).to include("By week:")
    expect(text).to match(/^\s+1\. /)
    expect(text).not_to include("By month:")
  end

  it "shows monthly breakdown for search windows longer than 30 days" do
    config = mock_config(
      mockEventCount: 80,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-03-15",
      mockSeed: 9
    )
    params, output = run_search_pipeline(
      config: config,
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 3, 15, 23, 59, 59)
    )
    text = plain(output)

    expect(params[:group_by]).to eq("month")
    expect(text).to include("By month:")
    expect(text).to include("January 2026")
    expect(text).to include("February 2026")
    expect(text).to include("March 2026")
    expect(text).not_to include("By week:")
  end

  it "reports zero events when search window misses the mock generation range" do
    config = mock_config(
      mockEventCount: 50,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-31",
      mockSeed: 1
    )
    params, output = run_search_pipeline(
      config: config,
      time_min: Time.new(2026, 8, 21),
      time_max: Time.new(2026, 9, 20, 23, 59, 59),
      description: "work"
    )
    text = plain(output)

    expect(params[:events]).to be_empty
    expect(text).to include("Events found: 0")
    expect(text).to include("Mock seed: 1")
    expect(text).to include("By month:")
    expect(text.lines.count { |l| l.start_with?("mock1 |") }).to eq(0)
  end

  it "produces identical TextRenderer output for the same mock seed" do
    build = lambda do
      config = mock_config(mockEventCount: 15, mockSeed: 55, mockEventTo: "2026-01-14")
      _params, output = run_search_pipeline(
        config: config,
        time_min: Time.new(2026, 1, 1),
        time_max: Time.new(2026, 1, 14, 23, 59, 59),
        description: "work"
      )
      output
    end

    expect(build.call).to eq(build.call)
  end

  it "computes total occupied time as count * duration for fixed-length events" do
    config = mock_config(
      mockEventCount: 10,
      mockEventFrom: "2026-01-01",
      mockEventTo: "2026-01-05",
      mockEventDurationMin: "4h",
      mockEventDurationMax: "4h",
      mockSeed: 2
    )
    params, output = run_search_pipeline(
      config: config,
      time_min: Time.new(2026, 1, 1),
      time_max: Time.new(2026, 1, 5, 23, 59, 59)
    )
    text = plain(output)

    expect(params[:totals][:event_count]).to eq(10)
    expect(params[:totals][:total_minutes]).to eq(10 * 4 * 60)
    expect(text).to match(/Total time occupied: 40h 0min \(5\.0 working days\)/)
  end
end
