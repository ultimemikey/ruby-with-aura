module Aura
  module Error
    module Suggestions
      module_function

      def closest_matches(query, candidates, limit: 3)
        needle = query.to_s.strip.downcase
        return [] if needle.empty?

        normalized = Array(candidates)
          .compact
          .map(&:to_s)
          .uniq

        normalized
          .map { |candidate| [candidate, score(needle, candidate.downcase)] }
          .sort_by { |(_candidate, candidate_score)| candidate_score }
          .select { |(_candidate, candidate_score)| candidate_score <= threshold_for(needle) }
          .first(limit)
          .map(&:first)
      end

      def score(left, right)
        levenshtein(left, right)
      end

      def threshold_for(value)
        case value.length
        when 0..4 then 1
        when 5..8 then 2
        else 3
        end
      end

      def levenshtein(left, right)
        return right.length if left.empty?
        return left.length if right.empty?

        previous = (0..right.length).to_a

        left.chars.each_with_index do |left_char, left_index|
          current = [left_index + 1]

          right.chars.each_with_index do |right_char, right_index|
            cost = left_char == right_char ? 0 : 1
            current << [
              current[right_index] + 1,
              previous[right_index + 1] + 1,
              previous[right_index] + cost
            ].min
          end

          previous = current
        end

        previous.last
      end
    end
  end
end
