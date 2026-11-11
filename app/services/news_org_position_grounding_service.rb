# frozen_string_literal: true

class NewsOrgPositionGroundingService
  # @lat: [[news-article-evidence#Grounding decisions]]

  NAME_MATCH_THRESHOLD = 0.9
  MAX_SUMMARY_LENGTH = 500
  MIN_AUTHORITY_CONFIDENCE = 0.7
  DEFAULT_DECISION_MODEL = "ScaleDown Classify Latest"
  MAX_ORG_NAME_CHARS = 200
  MAX_SPEAKER_ROLE_CHARS = 200
  MAX_SENTENCE_CHARS = 1_000

  SPOKESPERSON_ROLE_PATTERN = /\b(?:executive\s+director|president|vice\s+president|chair(?:person)?|policy\s+director|program\s+director|director|spokes(?:person|man|woman)|(?:general\s+|legal\s+)?counsel|founder|ceo|chief\s+executive\s+officer|(?:community\s+|lead\s+)?organizer|treasurer|secretary|statement\s+(?:from|by)|on\s+behalf\s+of|press\s+release|official\s+statement)\b/i

  MERE_MEMBER_PATTERN = /\b(?:(?:a\s+|an\s+)?(?:member\s+of|employee\s+(?:at|of)|worker\s+(?:at|for|with)|volunteer\s+(?:at|for|with)|resident\s+(?:who|of)|activist\s+(?:with|at)))\b/i

  PUBLIC_BODY_PATTERN = /\b(?:department|commission|authority|agency|bureau|administration|city\s+council|general\s+assembly|board\s+of\s+estimates|board\s+of\s+elections|board\s+of\s+education|mayor(?:'s)?\s+office|office\s+of\b|city\s+of\b|state\s+of\b|county\s+of\b)\b/i

  DIRECT_QUOTE_PATTERN = /["“][^"”\n]{3,}["”]|(?<!\w)['‘][^'’\n]{3,}['’](?!\w)/

  class << self
    def eligible_reporting_articles(bill)
      return BillNewsArticle.none if bill.nil?

      bill.bill_news_articles
        .eligible_for_synthesis
        .joins(:news_article)
        .where(news_articles: {article_kind: "reporting"})
    end

    def reporting_eligible?(bill)
      return false if bill.nil?

      eligible_reporting_articles(bill).exists?
    end

    def normalize_organization_name(name)
      return "" if name.blank?

      cleaned = name.to_s.strip
      cleaned = cleaned.sub(/\Athe\s+/i, "")
      cleaned = cleaned.sub(/[,\s]+(?:inc|llc|corp|corporation|co|company|ltd|limited)\.?\s*\z/i, "")
      cleaned.gsub(/[^\p{Alnum}\s]/, " ").strip.gsub(/\s+/, " ").downcase
    end

    def match_existing_organization(bill, org_name)
      return nil if bill.nil? || org_name.blank?

      target = normalize_organization_name(org_name)
      return nil if target.empty?

      orgs = Organization.where(sway_locale: bill.sway_locale).order(:id).to_a

      exact = orgs.find { |o| normalize_organization_name(o.name) == target }
      return exact if exact

      orgs.find do |o|
        norm_name = normalize_organization_name(o.name)
        next false if norm_name.empty?

        DidYouMean::JaroWinkler.distance(target, norm_name) >= NAME_MATCH_THRESHOLD
      end
    end

    def organization_has_users?(organization)
      return false if organization.nil?

      organization.user_organization_memberships.exists?
    end

    def public_body_name?(name)
      return false if name.blank?

      PUBLIC_BODY_PATTERN.match?(name.to_s)
    end

    def default_decision_adapter(decision_model: nil, route: nil)
      return nil if Rails.env.test?

      resolved_route = route || default_decision_route(decision_model: decision_model)
      return nil if resolved_route.nil?

      Llm::Client.build(provider: resolved_route.provider.to_s)
    rescue => e
      SwayLogging.warn(
        "news_grounding.adapter_unavailable",
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      nil
    end

    def filter_draft_positions(bill:, raw_positions:, snapshots: [], hearing_testimony_present: false, decision_adapter: :default, decision_model: nil)
      return [] if bill.nil? || raw_positions.blank?

      raw_list = Array(raw_positions)
      return [] if raw_list.empty?

      registry = build_source_registry(bill, snapshots)
      kept = []
      seen_orgs = Set.new
      cached_decision_adapter = (decision_adapter == :default) ? nil : decision_adapter
      cached_decision_model = decision_model
      decision_adapter_resolved = !(decision_adapter == :default)

      raw_list.each do |raw_entry|
        next unless raw_entry.is_a?(::Hash)

        entry = raw_entry.transform_keys(&:to_s)
        news_sourced = BillLlmProvisioning.draft_news_sourced?(entry)

        if !news_sourced
          next unless hearing_testimony_present

          org_name = entry["org_name"].to_s.strip
          next if org_name.blank?

          matched_org = match_existing_organization(bill, org_name)
          next if organization_has_users?(matched_org)

          canonical_name = matched_org ? matched_org.name : org_name
          norm_key = normalize_organization_name(canonical_name)
          next if norm_key.empty? || seen_orgs.include?(norm_key)

          seen_orgs.add(norm_key)
          kept << entry.merge("org_name" => canonical_name)
        else
          bna_id = entry["bill_news_article_id"]&.to_i
          tv_id = entry["text_version_id"]&.to_i
          excerpt = entry["evidence_excerpt"].to_s.strip
          org_name = entry["org_name"].to_s.strip

          next if bna_id.nil? || bna_id.zero?
          next if tv_id.nil? || tv_id.zero?
          next if excerpt.blank? || org_name.blank?

          source = registry[[bna_id, tv_id]]
          next if source.nil?

          text = source[:text].to_s
          offset = text.index(excerpt)
          next if offset.nil?

          window = text[[offset - 50, 0].max, excerpt.length + 100] || excerpt
          next unless direct_quote?(excerpt, window)

          next if public_body_name?(org_name)

          outlet_name = source[:outlet_name].to_s
          author_name = source[:author_name].to_s
          next if self_attribution?(org_name, outlet_name, author_name)

          matched_org = match_existing_organization(bill, org_name)
          next if organization_has_users?(matched_org)

          canonical_name = matched_org ? matched_org.name : org_name
          norm_key = normalize_organization_name(canonical_name)
          next if norm_key.empty? || seen_orgs.include?(norm_key)

          speaker_role = entry["speaker_role"].to_s
          sentence = extract_surrounding_sentence(text, offset, excerpt.length)

          if !decision_adapter_resolved && requires_decision_model?(speaker_role, sentence)
            route = default_decision_route(decision_model: decision_model)
            cached_decision_adapter = default_decision_adapter(decision_model: decision_model, route: route)
            cached_decision_model = decision_model.presence || route&.api_model
            decision_adapter_resolved = true
          end

          next unless valid_spokesperson_authority?(
            speaker_role,
            sentence,
            org_name: canonical_name,
            decision_adapter: (decision_adapter_resolved ? cached_decision_adapter : decision_adapter),
            decision_model: (decision_adapter_resolved ? cached_decision_model : decision_model)
          )

          seen_orgs.add(norm_key)

          source_url = source[:canonical_url].to_s
          article_title = source[:title].to_s
          excerpt_length = excerpt.length
          excerpt_paragraph = calculate_paragraph_index(text, offset)
          excerpt_page = calculate_page_number(text, offset)

          formatted_summary = format_news_summary(
            quote: extract_quote(excerpt),
            speaker_name: entry["speaker_name"],
            speaker_role: speaker_role,
            outlet_name: outlet_name,
            stance: entry["stance"] || entry["support"],
            source_url: source_url,
            org_name: canonical_name
          )

          enriched = entry.merge(
            "org_name" => canonical_name,
            "summary" => formatted_summary,
            "source_url" => source_url,
            "outlet_name" => outlet_name,
            "article_title" => article_title,
            "excerpt_offset" => offset,
            "excerpt_length" => excerpt_length,
            "excerpt_paragraph" => excerpt_paragraph,
            "excerpt_page" => excerpt_page
          )
          kept << enriched
        end
      end

      kept
    end

    def entry_still_grounded?(entry, bill:, decision_adapter: :default, decision_model: nil)
      return false unless entry.is_a?(::Hash)
      return false if bill.nil?
      return false if BillLlmProvisioning.draft_evidence_retracted?(entry)

      h = entry.transform_keys(&:to_s)
      bna_id = h["bill_news_article_id"]&.to_i
      tv_id = h["text_version_id"]&.to_i
      excerpt = h["evidence_excerpt"].to_s.strip
      org_name = h["org_name"].to_s.strip

      return false if bna_id.nil? || bna_id.zero?
      return false if tv_id.nil? || tv_id.zero?
      return false if excerpt.blank? || org_name.blank?
      return false if public_body_name?(org_name)

      bna = bill.bill_news_articles.find_by(id: bna_id)
      return false if bna.nil? || !bna.approved?
      return false unless bna.eligible_for_synthesis? || bna.eligible_for_testimony?
      return false unless bna.current_text_version_id == tv_id

      article = bna.news_article
      return false if self_attribution?(org_name, article&.outlet_name.to_s, article&.author_name.to_s)

      matched_org = match_existing_organization(bill, org_name)
      return false if organization_has_users?(matched_org)

      tv = bna.current_text_version
      return false if tv.nil? || !tv.usable_text?

      text = tv.text.to_s
      offset = text.index(excerpt)
      return false if offset.nil?

      window = text[[offset - 50, 0].max, excerpt.length + 100] || excerpt
      return false unless direct_quote?(excerpt, window)

      speaker_role = h["speaker_role"].to_s
      sentence = extract_surrounding_sentence(text, offset, excerpt.length)
      return false unless valid_spokesperson_authority?(
        speaker_role,
        sentence,
        org_name: org_name,
        decision_adapter: decision_adapter,
        decision_model: decision_model
      )

      true
    end

    private

    def default_decision_route(decision_model: nil)
      return nil if Rails.env.test?

      if decision_model.present?
        Llm::RouteResolver.resolve(
          model_choice: decision_model,
          purpose: :decision,
          blank_fallback: DEFAULT_DECISION_MODEL
        )
      else
        Llm::RouteResolver.resolve(
          purpose: :decision,
          blank_fallback: DEFAULT_DECISION_MODEL
        )
      end
    rescue => e
      SwayLogging.warn(
        "news_grounding.adapter_unavailable",
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      nil
    end

    def requires_decision_model?(speaker_role, sentence)
      has_spokesperson = SPOKESPERSON_ROLE_PATTERN.match?(speaker_role) || SPOKESPERSON_ROLE_PATTERN.match?(sentence)
      has_mere_member = MERE_MEMBER_PATTERN.match?(speaker_role) || MERE_MEMBER_PATTERN.match?(sentence)

      return false if has_mere_member || has_spokesperson

      speaker_role.present?
    end

    def build_source_registry(bill, snapshots)
      registry = {}

      snapshot_list = Array(snapshots).compact
      if snapshot_list.any?
        bna_ids = []
        tv_ids = []
        snapshot_list.each do |snap|
          (snap.captured_source_entries || []).each do |se|
            h = se.respond_to?(:to_h) ? se.to_h.stringify_keys : se
            bna_ids << h["bill_news_article_id"]&.to_i
            tv_ids << (h["text_version_id"] || h["news_article_text_version_id"])&.to_i
          end
        end
        bna_ids = bna_ids.compact.uniq
        tv_ids = tv_ids.compact.uniq

        bnas = BillNewsArticle.where(id: bna_ids).includes(:news_article).index_by(&:id)
        tvs = NewsArticleTextVersion.where(id: tv_ids).index_by(&:id)

        snapshot_list.each do |snap|
          (snap.captured_source_entries || []).each do |se|
            h = se.respond_to?(:to_h) ? se.to_h.stringify_keys : se
            b_id = h["bill_news_article_id"]&.to_i
            t_id = (h["text_version_id"] || h["news_article_text_version_id"])&.to_i
            next if b_id.nil? || t_id.nil?

            bna = bnas[b_id]
            tv = tvs[t_id]
            next if bna.nil? || tv.nil? || !tv.usable_text?

            registry[[b_id, t_id]] = {
              text: tv.text,
              canonical_url: bna.news_article&.canonical_url,
              outlet_name: bna.news_article&.outlet_name,
              title: bna.news_article&.title,
              author_name: bna.news_article&.author_name
            }
          end
        end
      elsif bill
        eligible_articles = bill.bill_news_articles
          .approved
          .includes(:news_article, :current_text_version)
          .select { |bna| bna.eligible_for_synthesis? || bna.eligible_for_testimony? }

        eligible_articles.each do |bna|
          tv = bna.current_text_version
          next if tv.nil? || !tv.usable_text?

          registry[[bna.id, tv.id]] = {
            text: tv.text,
            canonical_url: bna.news_article&.canonical_url,
            outlet_name: bna.news_article&.outlet_name,
            title: bna.news_article&.title,
            author_name: bna.news_article&.author_name
          }
        end
      end

      registry
    end

    def direct_quote?(excerpt, window)
      return true if DIRECT_QUOTE_PATTERN.match?(excerpt)

      stripped = excerpt.to_s.strip
      return false if stripped.empty?

      window.to_s.scan(DIRECT_QUOTE_PATTERN).any? { |q| q.include?(stripped) }
    end

    def valid_spokesperson_authority?(speaker_role, sentence, org_name: nil, decision_adapter: nil, decision_model: nil)
      has_spokesperson = SPOKESPERSON_ROLE_PATTERN.match?(speaker_role) || SPOKESPERSON_ROLE_PATTERN.match?(sentence)
      has_mere_member = MERE_MEMBER_PATTERN.match?(speaker_role) || MERE_MEMBER_PATTERN.match?(sentence)

      if has_mere_member
        return SPOKESPERSON_ROLE_PATTERN.match?(speaker_role) && SPOKESPERSON_ROLE_PATTERN.match?(sentence)
      end

      return true if has_spokesperson
      return false if speaker_role.blank?

      if decision_adapter == :default
        route = default_decision_route(decision_model: decision_model)
        adapter = default_decision_adapter(decision_model: decision_model, route: route)
        effective_model = decision_model.presence || route&.api_model
      else
        adapter = decision_adapter
        effective_model = decision_model
      end

      return false unless adapter

      if adapter.respond_to?(:generate_decisions)
        verify_with_decision_model(
          speaker_role: speaker_role,
          sentence: sentence,
          org_name: org_name,
          decision_adapter: adapter,
          decision_model: effective_model
        )
      else
        false
      end
    end

    def verify_with_decision_model(speaker_role:, sentence:, org_name:, decision_adapter:, decision_model:)
      model_id = decision_model.presence || Llm::RouteResolver.resolve(purpose: :decision, blank_fallback: DEFAULT_DECISION_MODEL).api_model

      sanitized_org = Llm::UntrustedTextBlock.neutralize(Llm::PromptLabel.collapse(org_name.to_s))[0, MAX_ORG_NAME_CHARS].to_s
      sanitized_role = Llm::UntrustedTextBlock.neutralize(Llm::PromptLabel.collapse(speaker_role.to_s))[0, MAX_SPEAKER_ROLE_CHARS].to_s
      sanitized_sentence = Llm::UntrustedTextBlock.neutralize(Llm::PromptLabel.collapse(sentence.to_s))[0, MAX_SENTENCE_CHARS].to_s

      state = {
        "org_name" => sanitized_org,
        "speaker_role" => sanitized_role,
        "sentence" => sanitized_sentence
      }
      questions = {
        "authority" => {
          "type" => "choice",
          "instructions" => "Does the speaker hold leadership or official spokesperson authority to state the organization's position in this sentence?",
          "criteria" => {
            "authorized_spokesperson" => "An officer, director, counsel, or authorized spokesperson speaking for the organization.",
            "official_statement" => "An official organizational statement.",
            "mere_member" => "A rank-and-file member, participant, or volunteer without leadership authority.",
            "unaffiliated" => "The speaker is not speaking on behalf of the organization."
          }
        }
      }

      response = decision_adapter.generate_decisions(model: model_id, state: state, questions: questions)
      return false unless response.is_a?(Hash)

      raw_answers = response["answers"] || response[:answers]
      return false unless raw_answers.is_a?(Hash)

      answer = raw_answers["authority"] || raw_answers[:authority]
      return false unless answer.is_a?(Hash)

      choice = (answer["choice"] || answer[:choice]).to_s
      probs = answer["probabilities"] || answer[:probabilities]
      choice_prob = probs.is_a?(Hash) ? (probs[choice] || probs[choice.to_sym]) : nil
      raw_conf = answer["confidence"] || answer[:confidence] || choice_prob

      return false unless raw_conf.is_a?(Float) || raw_conf.is_a?(Integer)
      return false unless raw_conf.to_f.finite? && raw_conf.to_f >= MIN_AUTHORITY_CONFIDENCE

      ["authorized_spokesperson", "official_statement"].include?(choice)
    rescue => e
      SwayLogging.warn(
        "news_grounding.decision_model_failed",
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      false
    end

    def self_attribution?(org_name, outlet_name, author_name)
      norm_org = normalize_organization_name(org_name)
      norm_outlet = normalize_organization_name(outlet_name)
      return true if norm_outlet.present? && norm_org == norm_outlet

      if author_name.present?
        norm_author = normalize_organization_name(author_name)
        return true if norm_author.present? && (norm_org == norm_author || norm_org.include?(norm_author))
      end

      false
    end

    def extract_surrounding_sentence(text, offset, length)
      before_text = text[0...offset] || ""
      after_text = text[(offset + length)..] || ""

      prev_boundary = before_text.rindex(/[.!?\n]/)
      sentence_start = prev_boundary ? prev_boundary + 1 : 0

      next_boundary = after_text.index(/[.!?\n]/)
      sentence_end = next_boundary ? (offset + length + next_boundary) : text.length

      text[sentence_start..sentence_end].to_s.strip
    end

    def calculate_paragraph_index(text, offset)
      prefix = text[0...offset] || ""
      paras = prefix.split(/\n\s*\n/)
      [paras.size, 1].max
    end

    def calculate_page_number(text, offset)
      prefix = text[0...offset] || ""
      if text.include?("\f")
        prefix.count("\f") + 1
      elsif text.match?(/(?:--- Page|\bPage\s+\d+\b)/i)
        prefix.scan(/(?:--- Page|\bPage\s+\d+\b)/i).size + 1
      end
    end

    def extract_quote(excerpt)
      if (m = excerpt.match(/["“]([^"”\n]{3,})["”]|(?<!\w)['‘]([^'’\n]{3,})['’](?!\w)/))
        m[1] || m[2]
      else
        excerpt.sub(/\A["“'‘]/, "").sub(/["”'’]\z/, "")
      end
    end

    def format_news_summary(quote:, speaker_name:, speaker_role:, outlet_name:, stance:, source_url:, org_name:)
      attribution =
        if speaker_name.present? && speaker_role.present?
          "#{speaker_name}, #{speaker_role}"
        elsif speaker_name.present?
          speaker_name
        elsif speaker_role.present? && !speaker_role.match?(/\A(?:official\s+statement|statement)\z/i)
          speaker_role
        else
          "Statement from #{org_name}"
        end

      stance_str = stance.to_s.capitalize
      formatted = "\"#{quote}\" — #{attribution} in #{outlet_name} (#{stance_str}). #{source_url}"
      formatted.truncate(MAX_SUMMARY_LENGTH)
    end
  end
end
