# frozen_string_literal: true

# @lat: [[voter-privacy-threshold]]
module VoteComparisonPrivacy
  MINIMUM_VOTERS = 10
  FINE_STEP_VOTERS = 20
  COARSE_STEP = 10
  FINE_STEP = 5

  def self.suppressed?(for_count, against_count)
    (for_count + against_count) < MINIMUM_VOTERS
  end

  def self.unanimous?(first_count, second_count)
    (first_count + second_count).positive? && (first_count.zero? || second_count.zero?)
  end

  def self.withheld?(first_count, second_count)
    suppressed?(first_count, second_count) || unanimous?(first_count, second_count)
  end

  # @lat: [[voter-privacy-threshold#Percentages are rounded to steps and a unanimous split is withheld]]
  def self.rounded_percentages(counts_by_key, voters:)
    total = counts_by_key.values.sum
    return nil if total.zero?

    step = (voters < FINE_STEP_VOTERS) ? COARSE_STEP : FINE_STEP
    steps_by_key = largest_remainder_steps(counts_by_key, total, step)
    give_empty_keys_a_step(counts_by_key, steps_by_key)
    steps_by_key.transform_values { |steps| steps * step }
  end

  def self.largest_remainder_steps(counts_by_key, total, step)
    divisor = step * total
    steps_by_key = counts_by_key.transform_values { |count| (count * 100) / divisor }
    leftover_steps = (100 / step) - steps_by_key.values.sum
    remainders = counts_by_key.transform_values { |count| (count * 100) % divisor }
    keys_by_remainder = counts_by_key.keys.sort_by.with_index { |key, index| [-remainders[key], index] }
    keys_by_remainder.first(leftover_steps).each { |key| steps_by_key[key] += 1 }
    steps_by_key
  end
  private_class_method :largest_remainder_steps

  def self.give_empty_keys_a_step(counts_by_key, steps_by_key)
    counts_by_key.each do |key, count|
      next unless count.positive? && steps_by_key[key].zero?

      steps_by_key[steps_by_key.key(steps_by_key.values.max)] -= 1
      steps_by_key[key] += 1
    end
  end
  private_class_method :give_empty_keys_a_step
end
