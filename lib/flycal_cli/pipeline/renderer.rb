# frozen_string_literal: true

module FlycalCli
  module Pipeline
    # Third pipeline layer: render aggregated results to a chosen format.
    class Renderer
      FORMATS = {
        "text" => "FlycalCli::Pipeline::TextRenderer",
        "json" => "FlycalCli::Pipeline::JsonRenderer"
      }.freeze

      def self.for(format)
        key = format.to_s.strip.downcase
        key = "text" if key.empty?
        class_name = FORMATS[key]
        raise FlycalCli::Error, "Unsupported format #{format.inspect}. Available: #{FORMATS.keys.join(", ")}" unless class_name

        Object.const_get(class_name).new
      end

      # @return [String] rendered output
      def render(params)
        raise NotImplementedError, "#{self.class}#render must be implemented"
      end
    end
  end
end
