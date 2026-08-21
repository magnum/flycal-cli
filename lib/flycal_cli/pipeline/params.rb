# frozen_string_literal: true

module FlycalCli
  module Pipeline
    # Mutable bag of CLI + derived parameters passed through the pipeline.
    class Params
      def initialize(initial = {})
        @data = {}
        initial.each { |k, v| self[k] = v }
      end

      def [](key)
        @data[key.to_sym]
      end

      def []=(key, value)
        @data[key.to_sym] = value
      end

      def fetch(key, default = nil, &block)
        if block
          @data.fetch(key.to_sym, &block)
        else
          @data.fetch(key.to_sym, default)
        end
      end

      def key?(key)
        @data.key?(key.to_sym)
      end

      def merge!(other)
        other.each { |k, v| self[k] = v }
        self
      end

      def to_h
        @data.dup
      end

      def each(&block)
        @data.each(&block)
      end
    end
  end
end
