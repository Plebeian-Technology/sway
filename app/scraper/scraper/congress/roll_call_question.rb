# frozen_string_literal: true

module Scraper
  module Congress
    # @lat: [[roll-call-identity#Identifying a congressional roll call#Why a wrong roll call raises rather than returns]]
    # @lat: [[congress-roll-calls#How RollCallQuestion separates passage from procedural motions]]
    class RollCallQuestion
      HOUSE_CONCURRENCE = "on motion to concur"

      HOUSE_OPENINGS = [
        "on passage",
        "on motion to suspend the rules and pass",
        "on motion to suspend the rules and agree",
        "on agreeing to the resolution",
        "on agreeing to the conference report",
        HOUSE_CONCURRENCE,
        "on overriding the veto"
      ].freeze

      HOUSE_REFUSED_OPENINGS = [
        "on ordering the previous question",
        "on motion to recommit",
        "on motion to commit",
        "on motion to table",
        "on agreeing to the amendment",
        "call by states",
        "call of the house",
        "election of the speaker"
      ].freeze

      SENATE_QUESTIONS = [
        "on passage of the bill",
        "on the nomination",
        "on the joint resolution",
        "on the resolution",
        "on the concurrent resolution",
        "on overriding the veto",
        "on cloture on the motion to proceed",
        "on the cloture motion"
      ].freeze

      SENATE_REFUSED_QUESTIONS = [
        "on the motion to proceed",
        "on the motion to table",
        "on the motion to reconsider",
        "on the motion to discharge",
        "on the motion to recommit",
        "on the motion to refer",
        "on the motion to adjourn",
        "on the motion for attendance",
        "on the decision of the chair",
        "on the point of order",
        "on the amendment"
      ].freeze

      # @lat: [[congress-roll-calls#How RollCallQuestion separates passage from procedural motions]]
      MOTION = "on the motion"

      CONCURRENCE = /\Amotion to concur\b/

      WITH_AMENDMENT = /\bwith (?:an |a further )?amendment\b/

      BRACKETED = /\s*\(([^)]*)\)\s*\z/

      attr_reader :chamber, :question, :title

      def initialize(chamber:, question:, title: nil)
        @chamber = chamber.to_sym
        asked = self.class.normalize(question)
        bracketed = asked[BRACKETED, 1]
        @question = asked.sub(BRACKETED, "")
        @title = self.class.normalize(title).presence || bracketed.to_s
      end

      def self.normalize(value)
        value.to_s.downcase.gsub(/\s+/, " ").strip
      end

      # @lat: [[congress-roll-calls#A vote on something else is not a position on the bill]]
      def counts_as_position?
        position_question? && !concurrence_with_amendment?
      end

      # @lat: [[congress-roll-calls#How RollCallQuestion separates passage from procedural motions]]
      def known?
        position_question? || refused.any? { |phrase| refused_match?(phrase) }
      end

      def to_s
        title.present? ? "#{question} (#{title})" : question
      end

      private

      def position_question?
        case chamber
        when :house then HOUSE_OPENINGS.any? { |opening| question.start_with?(opening) }
        when :senate then senate_position?
        else false
        end
      end

      # @lat: [[congress-roll-calls#How RollCallQuestion separates passage from procedural motions]]
      def concurrence_with_amendment?
        case chamber
        when :house then question.start_with?(HOUSE_CONCURRENCE) && WITH_AMENDMENT.match?(question)
        when :senate then question == MOTION && WITH_AMENDMENT.match?(title)
        else false
        end
      end

      def senate_position?
        return true if SENATE_QUESTIONS.include?(question)

        question == MOTION && CONCURRENCE.match?(title)
      end

      # @lat: [[congress-roll-calls#How RollCallQuestion separates passage from procedural motions]]
      def refused
        case chamber
        when :house then HOUSE_REFUSED_OPENINGS
        when :senate then SENATE_REFUSED_QUESTIONS + [MOTION]
        else []
        end
      end

      def refused_match?(phrase)
        (chamber == :house) ? question.start_with?(phrase) : question == phrase
      end
    end
  end
end
