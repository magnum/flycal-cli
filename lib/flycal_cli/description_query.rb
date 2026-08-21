# frozen_string_literal: true

module FlycalCli
  # Shared helpers for --description filtering and --groupBy description.
  #
  # OR terms are separated by "|" (also "," for grouping convenience).
  # Matching is case-insensitive against event summary and description.
  module DescriptionQuery
    module_function

    def patterns(query)
      query.to_s.split(/[|,]/).map(&:strip).reject(&:empty?)
    end

    def match?(event_summary, event_description, query)
      terms = patterns(query)
      return true if terms.empty?

      summary = event_summary.to_s.downcase
      description = event_description.to_s.downcase
      terms.any? { |term| summary.include?(term.downcase) || description.include?(term.downcase) }
    end

    def match_term?(event_summary, event_description, term)
      needle = term.to_s.downcase
      return false if needle.empty?

      event_summary.to_s.downcase.include?(needle) ||
        event_description.to_s.downcase.include?(needle)
    end
  end
end
