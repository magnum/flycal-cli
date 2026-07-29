#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"

ROOT = File.expand_path(__dir__)
VERSION_FILE = File.join(ROOT, "lib/flycal_cli/version.rb")
GEMSPEC = File.join(ROOT, "flycal-cli.gemspec")

def abort_with(message)
  warn message
  exit 1
end

def run!(command, **options)
  puts "$ #{command.join(" ")}"
  success = system(*command, **options)
  abort_with("Command failed: #{command.join(" ")}") unless success
end

def read_version
  content = File.read(VERSION_FILE)
  match = content.match(/VERSION\s*=\s*['"]([^'"]+)['"]/)
  abort_with("Could not read version from #{VERSION_FILE}") unless match

  match[1]
end

def parse_version(version)
  parts = version.split(".").map(&:to_i)
  abort_with("Invalid version format: #{version.inspect}. Use major.minor.patch.") unless parts.length == 3 && parts.all? { |p| p >= 0 }

  parts
end

def bump_minor(version)
  major, minor, = parse_version(version)
  "#{major}.#{minor + 1}.0"
end

def valid_version?(version)
  version.match?(/\A\d+\.\d+\.\d+\z/)
end

def write_version(version)
  content = <<~RUBY
    # frozen_string_literal: true

    module FlycalCli
      VERSION = '#{version}'
    end
  RUBY

  File.write(VERSION_FILE, content)
end

def prompt(message, default: nil)
  print message
  input = $stdin.gets
  abort_with("Aborted.") if input.nil?

  value = input.strip
  value = default if value.empty? && default
  value
end

def confirm?(message)
  answer = prompt("#{message} [y/N]: ")
  %w[y yes].include?(answer.downcase)
end

Dir.chdir(ROOT)

current_version = read_version
proposed_version = bump_minor(current_version)

puts "Current version: #{current_version}"
new_version = prompt("New version [#{proposed_version}]: ", default: proposed_version)
abort_with("Invalid version: #{new_version.inspect}") unless valid_version?(new_version)

if new_version == current_version
  puts "Version unchanged (#{current_version}). Proceeding with release of existing version."
else
  write_version(new_version)
  puts "Updated #{VERSION_FILE} -> #{new_version}"

  run!(["git", "add", VERSION_FILE])
  run!(["git", "commit", "-m", "Release version #{new_version}."])
end

gem_name = "flycal-cli-#{new_version}.gem"
run!(["gem", "build", GEMSPEC])

gem_path = File.join(ROOT, gem_name)
abort_with("Gem file not found: #{gem_path}") unless File.exist?(gem_path)

if confirm?("Push #{gem_name} to RubyGems?")
  run!(["gem", "push", gem_path])
  puts "Released flycal-cli #{new_version}."
else
  puts "Skipped push. Built gem: #{gem_path}"
end
