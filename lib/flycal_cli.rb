# frozen_string_literal: true

require "flycal_cli/version"
require "flycal_cli/config"
require "flycal_cli/auth"
require "flycal_cli/duration_parser"
require "flycal_cli/calendar_service"
require "flycal_cli/slot_finder"
require "flycal_cli/slot_formatter"
require "flycal_cli/cli"

module FlycalCli
  class Error < StandardError; end
end
