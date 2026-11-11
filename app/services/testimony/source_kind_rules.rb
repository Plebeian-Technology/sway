# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-attachment-rules#Source-kind rule ordering and evidence boundaries]]
  module SourceKindRules
    KINDS = %i[named_organization public_body person_speaking_for_org person_speaking_for_self].freeze #: Array[Testimony::SourceKindRules::kind]

    Result = Data.define(:kind, :phrase, :role, :sender, :org_name)

    # @lat: [[testimony-attachment-rules#What a sender's domain is not allowed to decide]]
    AGENCY_NOUNS = %w[department commission authority agency].freeze
    AGENCY_NOUN_SOURCE = "(#{AGENCY_NOUNS.map { |noun| Testimony::ExtractedText.phrase_source(noun) }.join("|")})"
    REPORT_AGENCY_NOUNS = (AGENCY_NOUNS + %w[board office]).freeze
    REPORT_AGENCY_NOUN_SOURCE = "(#{REPORT_AGENCY_NOUNS.map { |noun| Testimony::ExtractedText.phrase_source(noun) }.join("|")})"
    PUBLIC_BODY_PHRASES = ["on behalf of the", "testifying for the"].freeze
    PUBLIC_BODY_PATTERNS = (
      PUBLIC_BODY_PHRASES.map { |phrase|
        /\b#{Testimony::ExtractedText.phrase_source(phrase)}\b[^\n.]{0,40}\b#{AGENCY_NOUN_SOURCE}\b/i
      } + [
        /\b(?:the\s+)?#{REPORT_AGENCY_NOUN_SOURCE}\b(?:[^\n.]|\n(?![ \t]*\n)){0,50}\s+#{Testimony::ExtractedText.phrase_source("is herein reporting on")}\b/i,
        /\b#{Testimony::ExtractedText.phrase_source("prepared by the staff of")}(?:\s+the)?\s+#{REPORT_AGENCY_NOUN_SOURCE}\b/i,
        /\b#{Testimony::ExtractedText.phrase_source("at its regular meeting of")}\b(?:[^\n.]|\n(?![ \t]*\n)){0,60}\bthe\s+(?:(?:(?-i:[A-Z][a-zA-Z0-9&'-]*)|of|for|and|the|on)\s+){0,6}#{REPORT_AGENCY_NOUN_SOURCE}(?:\s+(?:(?-i:[A-Z][a-zA-Z0-9&'-]*)|of|for|and|the|on)){0,6}\s+#{Testimony::ExtractedText.phrase_source("considered")}\b/i,
        /^[ \t]*(?-i:#{Testimony::ExtractedText.phrase_source("BILL SYNOPSIS")})[ \t]*$[\s\S]{0,800}\b#{REPORT_AGENCY_NOUN_SOURCE}\b/i,
        /\bthe\s+(?:[A-Z][a-zA-Z]+\s+){0,3}#{REPORT_AGENCY_NOUN_SOURCE}(?:\s+of\s+[A-Z][a-zA-Z]+)?\s+#{Testimony::ExtractedText.phrase_source("wishes to thank")}\b[^\n.]{0,80}\bstudy\b/i
      ]
    ).freeze

    # @lat: [[testimony-attachment-rules#What a sender's domain is not allowed to decide]]
    LETTERHEAD_NOUN_SOURCE = "(#{AGENCY_NOUNS.map { |noun| Regexp.escape(noun.upcase) }.join("|")}|OFFICE|BOARD(?!\\s+OF\\s+(?:DIRECTORS|TRUSTEES|GOVERNORS)))"
    LETTERHEAD_LINE_PATTERN = /^[ \t]*+(?=[A-Z0-9])(?=[^\n]{0,80}\b#{LETTERHEAD_NOUN_SOURCE}\b)[A-Z0-9][A-Z0-9&,'.\- \t]{3,79}[ \t]*$/
    SALUTATION_PATTERN = /^[ \t]*(?:dear\b|to[ \t]+the[ \t]+(?:honorable|city[ \t]+council|council|committee|chair|members|mayor)\b|the[ \t]+honorable\b|honorable\b|good[ \t]+(?:morning|afternoon|evening)\b|members[ \t]+of[ \t]+the\b|hello\b|chair(?:man|woman|person)?\b|i[ \t]+(?:am[ \t]+writing|write)\b|(?:sincerely|respectfully|best[ \t]+regards|warm[ \t]+regards|regards|cordially)\b)/i
    LETTERHEAD_WINDOW_CHARS = 1_200

    # @lat: [[testimony-attachment-rules#Source-kind rule ordering and evidence boundaries]]
    ORGANIZATION_NOUNS = [
      "coalition", "association", "union", "alliance", "society", "foundation",
      "council", "committee", "group", "organization", "chamber of commerce"
    ].freeze
    ORGANIZATION_NOUN_SOURCE =
      "(#{ORGANIZATION_NOUNS.map { |noun| Testimony::ExtractedText.phrase_source(noun) }.join("|")})"
    OWN_VOICE_PHRASES = ["our organization", "we are writing", "we represent", "we urge"].freeze
    NAMED_ORGANIZATION_PATTERNS = [
      /\b#{Testimony::ExtractedText.phrase_source("on behalf of")}\b[^\n.,;]{0,60}\b#{ORGANIZATION_NOUN_SOURCE}\b/i,
      *OWN_VOICE_PHRASES.map { |phrase| /\b#{Testimony::ExtractedText.phrase_source(phrase)}\b/i }
    ].freeze

    ROLE_TITLES = [
      "executive director", "president", "vice president", "chair", "chairperson", "policy director",
      "program manager", "program director", "board member", "founder", "chief executive officer",
      "community organizer", "treasurer", "secretary"
    ].freeze
    ROLE_TITLE_PATTERN = /\b(#{ROLE_TITLES.map { |title| Testimony::ExtractedText.phrase_source(title) }.join("|")})\b/i

    ORG_AFFILIATION_PATTERN = /\b(?:of|at|for|with)\s+((?:the\s+)?[A-Z][\w&',.-]*(?:\s+(?:of\s+)?[A-Z][\w&',.-]*){0,6})/
    ORG_AFFILIATION_WINDOW_CHARS = 80

    class << self
      # @lat: [[testimony-attachment-rules#Source-kind rule ordering and evidence boundaries]]
      def classify(text, sender_address: nil)
        normalized = text.to_s

        if named_organization?(normalized)
          return Result.new(kind: :named_organization, phrase: nil, role: nil, sender: nil, org_name: nil)
        end
        if public_body?(normalized)
          return Result.new(kind: :public_body, phrase: nil, role: nil, sender: nil, org_name: nil)
        end

        role, phrase, org_name = person_speaking_for_org_evidence(normalized)
        if role && phrase && sender_address.present?
          return Result.new(kind: :person_speaking_for_org, phrase: phrase, role: role, sender: sender_address, org_name: org_name)
        end

        Result.new(kind: :person_speaking_for_self, phrase: nil, role: nil, sender: nil, org_name: nil)
      end

      private

      def public_body?(text)
        PUBLIC_BODY_PATTERNS.any? { |pattern| pattern.match?(text) } || letterhead?(text)
      end

      def letterhead?(text)
        LETTERHEAD_LINE_PATTERN.match?(letterhead_region(text))
      end

      def letterhead_region(text)
        body = Testimony::ExtractedText.strip_envelope(text)
        greeting = SALUTATION_PATTERN.match(body)
        # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
        greeting_at = greeting&.begin(0)
        limit = greeting_at.nil? ? LETTERHEAD_WINDOW_CHARS : [greeting_at, LETTERHEAD_WINDOW_CHARS].min
        body[0, limit].to_s
      end

      def named_organization?(text)
        return false if public_body?(text)

        NAMED_ORGANIZATION_PATTERNS.any? { |pattern| pattern.match?(text) }
      end

      def person_speaking_for_org_evidence(text)
        role_match = ROLE_TITLE_PATTERN.match(text)
        return [nil, nil, nil] if role_match.nil?

        # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
        role_end = role_match.end(0)
        return [nil, nil, nil] if role_end.nil?

        window = text[role_end, ORG_AFFILIATION_WINDOW_CHARS].to_s
        org_match = ORG_AFFILIATION_PATTERN.match(window)
        return [nil, nil, nil] if org_match.nil?

        role = role_match[0].strip.squeeze(" ")
        phrase = "#{role} #{org_match[0]}".squeeze(" ").strip
        org_name = org_match[1].squeeze(" ").strip
        [role, phrase, org_name]
      end
    end
  end
end
