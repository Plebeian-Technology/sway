# frozen_string_literal: true

# @lat: [[parse-sections-fuzzy-ratio-design#Why it is hand-rolled]]
class ParseSectionsService
  module FuzzyRatio
    module_function

    def ratio(a, b)
      return 100 if a == b
      return 0 if a.empty? || b.empty?
      dist = levenshtein(a, b)
      max_len = [a.length, b.length].max
      ((1.0 - (dist.to_f / max_len)) * 100).round
    end

    # @lat: [[parse-sections-fuzzy-ratio-design#Why the two-row implementation needs no reset between passes]]
    def levenshtein(a, b)
      m = a.length
      n = b.length
      prev = (0..n).to_a
      curr = Array.new(n + 1, 0)
      (1..m).each do |i|
        curr[0] = i
        (1..n).each do |j|
          cost = (a[i - 1] == b[j - 1]) ? 0 : 1
          curr[j] = [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].min
        end
        prev, curr = curr, prev
      end
      prev[n]
    end
  end
end
