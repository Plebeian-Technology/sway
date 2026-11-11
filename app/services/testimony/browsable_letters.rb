# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-letters#Selecting browsable constituent letters]]
  class BrowsableLetters
    Entry = Data.define(:position, :label, :stance, :body_text)

    ALLOWED_STANCES = %w[support oppose neutral].freeze
    GOVERNMENT_SENDER_DOMAIN_PATTERN = /\A(?:[\w-]+\.)*(?:baltimorecity\.gov|baltimorecouncil\.com|baltimorepolice\.org|bcps\.k12\.md\.us|maryland\.gov|mgaleg\.maryland\.gov|mdcourts\.gov|state\.md\.us|mail\.house\.gov|senate\.gov)\z/i
    GOVERNMENT_ADMIN_CORRESPONDENCE_PATTERN = %r{
      \b(?:
        bill[ \t]+file|hearing[ \t]+record|committee[ \t]+record|agency[ \t]+report|fiscal[ \t]+note
        |
        for[ \t]+form[ \t]+and[ \t]+legal[ \t]+sufficiency
        |
        no[ \t]+objection[ \t]+to[ \t]+the[ \t]+passage
        |
        scheduling[ \t]+of[ \t]+the[ \t]+hearing
        |
        attached[ \t]+(?:is|are|please[ \t]+find)
      )\b
    }mix

    class << self
      def for_bill(bill)
        new(bill).for_bill
      end

      def counts_for_bill(bill)
        new(bill).counts_for_bill
      end

      def counts_from_entries(entries)
        counts = {total: 0, support: 0, oppose: 0, neutral: 0}
        Array(entries).each do |entry|
          counts[:total] += 1
          case entry.stance
          when "support" then counts[:support] += 1
          when "oppose" then counts[:oppose] += 1
          else counts[:neutral] += 1
          end
        end
        counts
      end
    end

    def initialize(bill)
      @bill = bill
    end

    def for_bill
      bill = @bill
      return [] if bill.nil?

      provisioning = bill.bill_llm_provisioning
      return [] if provisioning.nil?

      cleaned_at = provisioning.cleaned_testimony_at
      fetched_at = provisioning.testimony_fetched_at
      return [] if cleaned_at && fetched_at && cleaned_at < fetched_at

      cleaned = provisioning.cleaned_testimony
      return [] unless cleaned.is_a?(Hash) && cleaned.present?

      letters = cleaned["letters"]
      full_text = cleaned["text"].to_s
      return [] unless letters.is_a?(Array) && letters.present? && full_text.present?

      individual_hashes = provisioning.individual_campaign_draft_hash_list.to_set
      rejected_hashes = provisioning.rejected_campaign_draft_hash_list.to_set
      approved_hashes = if individual_hashes.any?
        approved_campaign_draft_hashes
      else
        Set.new
      end

      draft_id_by_position = build_draft_id_by_position(cleaned["campaign_drafts"])

      eligible_letters = letters.select do |letter|
        letter_eligible?(letter, draft_id_by_position, individual_hashes, rejected_hashes, approved_hashes)
      end

      sorted_letters = eligible_letters.sort_by { |letter| parse_int(letter["position"]) || 0 }

      entries = []
      counter = 0

      sorted_letters.each do |letter|
        pos = parse_int(letter["position"])
        offset = parse_int(letter["character_offset"])
        length = parse_int(letter["characters"])
        next if pos.nil? || offset.nil? || length.nil? || offset < 0 || length <= 0

        raw_body = full_text[offset, length].to_s
        next if Testimony::ExtractedText.over_constituent_page_limit?(raw_body)

        body_text = extract_clean_body(raw_body, letter["sender_address"], letter["sender_domain"])
        next if body_text.blank?

        counter += 1
        stance = normalize_stance(letter["stance"])
        entries << Entry.new(
          position: pos,
          label: "Constituent Letter ##{counter}",
          stance: stance,
          body_text: body_text
        )
      end

      entries
    end

    def counts_for_bill
      self.class.counts_from_entries(for_bill)
    end

    private

    def parse_int(val)
      return val if val.is_a?(Integer)
      return nil if val.nil? || val == true || val == false

      Integer(val.to_s, 10, exception: false)
    end

    def extract_clean_body(raw_body, sender_address = nil, sender_domain = nil)
      body = raw_body.to_s
      if body.include?("\f")
        pages = body.split("\f", -1)
        pages.pop while pages.length > 1 && Testimony::ExtractedText.print_header_stub?(pages.last)
        body = pages.join("\f")
      end

      cleaned = strip_leading_wrappers_and_envelopes(body)
      cleaned = Testimony::ExtractedText.strip_recipient_headers(cleaned).strip
      if sender_address.present?
        addr_pattern = Regexp.new(Regexp.escape(sender_address.to_s), Regexp::IGNORECASE)
        cleaned = cleaned.gsub(addr_pattern, "").strip
      end
      return "" if sender_address.blank? && (/\A\d+[ \t]*\n/.match?(cleaned) || /\((?:City[ \t]+Council|Mayor|Comptroller)\)/i.match?(cleaned)) && Testimony::ExtractedText.print_header_stub?(cleaned)
      return "" if internal_correspondence_body?(cleaned, sender_address, sender_domain)

      Testimony::ExtractedText.unwrap_body_paragraphs(cleaned)
    end

    def internal_correspondence_body?(cleaned, sender_address, sender_domain)
      return true if Testimony::BoilerplateRemover.internal_routing_note?(cleaned)
      return false unless government_sender?(sender_address, sender_domain)
      return false if /\b(?:as[ \t]+a[ \t]+(?:resident|homeowner|voter|constituent|taxpayer|neighbor)|not[ \t]+for[ \t]+my[ \t]+employer)\b/i.match?(cleaned)

      GOVERNMENT_ADMIN_CORRESPONDENCE_PATTERN.match?(cleaned)
    end

    def government_sender?(sender_address, sender_domain)
      domain = sender_domain.to_s.strip
      domain = sender_address.to_s.split("@", 2).last.to_s.strip if domain.empty? && sender_address.to_s.include?("@")
      return false if domain.empty?

      GOVERNMENT_SENDER_DOMAIN_PATTERN.match?(domain)
    end

    def strip_leading_wrappers_and_envelopes(text)
      current = text
      2.times do
        lines = current.split("\n")
        while lines.first
          if lines.first.strip.empty? || forward_divider_line?(lines.first)
            lines.shift
          elsif lines.length >= 2 &&
              Testimony::ExtractedText::QUOTE_OPENING_MARKER.match?("#{lines[0].to_s.strip} #{lines[1].to_s.strip}")
            lines.shift(2)
          else
            break
          end
        end
        candidate = lines.join("\n")
        stripped = Testimony::ExtractedText.strip_envelope(candidate)
        break if stripped == current

        current = stripped
      end
      current
    end

    def forward_divider_line?(line)
      trimmed = line.to_s.strip
      Testimony::ExtractedText::FORWARD_OR_REPLY_LINE_MARKERS.any? { |pat| pat.match?(trimmed) } ||
        Testimony::ExtractedText::QUOTE_OPENING_MARKER.match?(trimmed)
    end

    def build_draft_id_by_position(campaign_drafts)
      mapping = {}
      Array(campaign_drafts).each do |draft|
        next unless draft.is_a?(Hash)

        draft_id = draft["id"].to_s.strip
        next if draft_id.empty?

        Array(draft["letter_positions"]).each do |pos|
          parsed_pos = parse_int(pos)
          next if parsed_pos.nil?

          mapping[parsed_pos] = draft_id
        end
      end
      mapping
    end

    def letter_eligible?(letter, draft_id_by_position, individual_hashes, rejected_hashes, approved_hashes)
      return false unless letter.is_a?(Hash)
      return false if letter["excluded"] == true || letter["excluded"].to_s == "true"
      return false unless letter["source_kind"].to_s == "person_speaking_for_self"
      return false if letter["repeat"] == true || letter["repeat"].to_s == "true" || letter["repeat_of_position"].present?

      parsed_pos = parse_int(letter["position"])
      return false if parsed_pos.nil? || parsed_pos < 0

      draft_id = letter["campaign_draft_id"].presence&.to_s&.strip || draft_id_by_position[parsed_pos]

      return false if draft_id.present? && (approved_hashes.include?(draft_id) || rejected_hashes.include?(draft_id))

      campaign_origin = letter["campaign_origin"] == true || letter["campaign_origin"].to_s == "true" || draft_id.present?
      if campaign_origin
        return false if draft_id.blank?
        return false unless individual_hashes.include?(draft_id)
      end

      true
    end

    def approved_campaign_draft_hashes
      bill = @bill
      return Set.new if bill.nil?

      campaigns = bill.campaigns
      if campaigns.loaded?
        campaigns.filter_map { |c| c.source_campaign_draft_hash.presence&.to_s }.to_set
      else
        campaigns.where.not(source_campaign_draft_hash: [nil, ""]).pluck(:source_campaign_draft_hash).map(&:to_s).to_set
      end
    end

    def normalize_stance(raw)
      stance = raw.to_s
      ALLOWED_STANCES.include?(stance) ? stance : "neutral"
    end
  end
end
