# frozen_string_literal: true

module FlycalCli
  # Cross-platform clipboard helper.
  # Prefers: pbcopy (macOS) → wl-copy (Wayland) → xclip (X11) → clip (Windows).
  module Clipboard
    module_function

    TOOLS = [
      { name: :pbcopy, command: %w[pbcopy] },
      { name: :wl_copy, command: %w[wl-copy] },
      { name: :xclip, command: %w[xclip -selection clipboard] },
      { name: :clip, command: %w[clip] }
    ].freeze

    def copy(text)
      tool = available_tool
      return nil unless tool

      IO.popen(tool[:command], "w") { |io| io.write(text.to_s) }
      return nil unless $?.success?

      tool[:name].to_s
    rescue StandardError
      nil
    end

    def available?
      !available_tool.nil?
    end

    def available_tool
      TOOLS.find { |tool| command_exists?(tool[:command].first) }
    end

    def command_exists?(name)
      exts =
        if Gem.win_platform?
          ENV.fetch("PATHEXT", ".EXE;.BAT;.CMD").split(";").reject(&:empty?)
        else
          [""]
        end

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        next false if dir.to_s.empty?

        exts.any? do |ext|
          path = File.join(dir, "#{name}#{ext}")
          File.file?(path) && File.executable?(path)
        end
      end
    end
  end
end
