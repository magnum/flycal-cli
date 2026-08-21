# frozen_string_literal: true

module FlycalCli
  module Pipeline
    # Orchestrates Retriever → Aggregator → Renderer for search.
    class SearchPipeline
      def initialize(calendar_service)
        @service = calendar_service
      end

      def run(params)
        Retriever.new(@service).call(params)
        Aggregator.new.call(params)
        Renderer.for(params[:format]).render(params)
      end
    end
  end
end
