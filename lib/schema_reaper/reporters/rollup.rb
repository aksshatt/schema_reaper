# frozen_string_literal: true

module SchemaReaper
  module Reporters
    # Groups findings that say the same thing about different targets.
    #
    # A report of 37 missing foreign-key indexes repeats one sentence 37 times,
    # varying only the table and column. Collapsing those into a single entry
    # with its targets listed keeps every fact and drops the repetition.
    module Rollup
      # Findings that differ only in which table and column they name carry no
      # new information per line. At or above this many, roll them up.
      THRESHOLD = 4

      module_function

      # @return [Array(Array<[key, Array<Finding>]>, Array<Finding>)]
      #   the groups worth rolling up (largest first), and the findings to
      #   spell out individually
      def partition(findings)
        by_shape = findings.group_by { |f| key_for(f) }
        big, small = by_shape.partition { |_key, group| group.size >= THRESHOLD }
        [big.sort_by { |_key, group| -group.size }, small.flat_map { |_key, group| group }]
      end

      def key_for(finding)
        [finding.type, shape(evidence_line(finding), finding), shape(finding.suggested_fix, finding)]
      end

      def evidence_line(finding)
        finding.evidence.join(" · ")
      end

      # Masks the names a finding is about, each with its own placeholder, so
      # two findings saying the same thing about different targets compare
      # equal -- and so the rolled-up fix still reads as a template.
      #
      # The lookarounds matter: without them, masking
      # index_users_on_team_id would also eat it out of
      # index_users_on_team_id_and_state, making two findings about different
      # covering indexes look identical.
      def shape(text, finding)
        replacements(finding).reduce(text) do |acc, (name, token)|
          acc.gsub(/(?<!\w)#{Regexp.escape(name)}(?!\w)/, token)
        end
      end

      def replacements(finding)
        [[finding.table, "<table>"], [finding.column, "<column>"], [finding.index, "<index>"]]
          .reject { |name, _| name.nil? || name.empty? }
          .sort_by { |name, _| -name.length }
      end
    end
  end
end
