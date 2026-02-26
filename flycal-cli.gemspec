# frozen_string_literal: true

require_relative "lib/flycal_cli/version"

Gem::Specification.new do |spec|
  spec.name = "flycal-cli"
  spec.version = FlycalCli::VERSION
  spec.authors = ["flycal-cli"]
  spec.email = [""]

  spec.summary = "CLI per accedere ai calendari Google"
  spec.description = "flycal-cli permette di connettersi al proprio account Google e gestire i calendari da riga di comando"
  spec.homepage = "https://github.com/your-username/flycal-cli"
  spec.required_ruby_version = ">= 3.1.0"
  spec.license = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/your-username/flycal-cli"
  spec.metadata["changelog_uri"] = "https://github.com/your-username/flycal-cli/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib,bin}/**/*", "LICENSE", "README.md"].select { |f| File.file?(f) }
  end
  spec.bindir = "bin"
  spec.executables = ["flycal"]
  spec.require_paths = ["lib"]

  spec.add_dependency "google-apis-calendar_v3", "~> 0.51"
  spec.add_dependency "googleauth", "~> 1.8"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "webrick", "~> 1.8"
end
