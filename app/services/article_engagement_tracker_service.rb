# frozen_string_literal: true

class ArticleEngagementTrackerService
  # @lat: [[partner-article-engagement#End-to-end attribution lifecycle]]
  def self.track_click(article_bill:)
    return false unless article_bill

    id = article_bill.is_a?(ArticleBill) ? article_bill.id : article_bill.to_i
    ArticleBill.increment_counter(:clicks_count, id)
    true
  end

  def self.track_registration(attribution_key:)
    return false if attribution_key.blank?

    article_bill = resolve_article_bill(attribution_key: attribution_key)
    return false unless article_bill

    ArticleBill.increment_counter(:registrations_count, article_bill.id)
    true
  end

  # @lat: [[partner-article-engagement#Privacy guarantees and k-anonymity]]
  def self.track_vote(bill:, stance:, attribution_key:)
    return false if attribution_key.blank? || bill.blank? || stance.blank?

    bill_id = bill.is_a?(Bill) ? bill.id : bill.to_i
    article_bill = resolve_article_bill(attribution_key: attribution_key, bill_id: bill_id)
    return false unless article_bill

    ArticleBill.increment_counter(:votes_count, article_bill.id)

    stance_str = stance.to_s.upcase.strip
    if pro_stance?(stance_str)
      ArticleBill.increment_counter(:pro_votes_count, article_bill.id)
    elsif con_stance?(stance_str)
      ArticleBill.increment_counter(:con_votes_count, article_bill.id)
    end

    true
  end

  def self.resolve_article_bill(attribution_key:, bill_id: nil)
    key = attribution_key.to_s.strip
    return nil if key.blank?

    bill_id_int = if bill_id.blank?
      nil
    elsif bill_id.is_a?(Bill)
      bill_id.id
    else
      bill_id.to_i
    end

    if key.match?(/\A\d+\z/)
      ab = ArticleBill.find_by(id: key.to_i)
      return (bill_id_int.nil? || ab&.bill_id == bill_id_int) ? ab : nil
    end

    if key.start_with?("partner:")
      parts = key.split(":")
      partner_slug = parts[1].presence
      ref = parts[2..]&.join(":")&.presence

      if partner_slug.present?
        if bill_id_int.present?
          scope = ArticleBill.where(partner_slug: partner_slug, bill_id: bill_id_int)

          if ref.present?
            id_match = ref.match(/\A(?:ab:)?(\d+)\z/)
            if id_match
              ab = scope.find_by(id: id_match[1].to_i)
              return ab if ab
            end

            ab = scope.find_by(article_url: ref)
            return ab if ab

            safe_ref = ActiveRecord::Base.sanitize_sql_like(ref)
            ab = scope.find_by("article_url LIKE ? ESCAPE '\\'", "%#{safe_ref}%")
            return ab if ab

            return nil
          end

          return scope.order(created_at: :desc).first
        else
          if ref.present?
            id_match = ref.match(/\A(?:ab:)?(\d+)\z/)
            if id_match
              ab = ArticleBill.find_by(id: id_match[1].to_i, partner_slug: partner_slug)
              return ab if ab
            end

            ab = ArticleBill.find_by(partner_slug: partner_slug, article_url: ref)
            return ab if ab

            safe_ref = ActiveRecord::Base.sanitize_sql_like(ref)
            ab = ArticleBill.where(partner_slug: partner_slug)
              .find_by("article_url LIKE ? ESCAPE '\\'", "%#{safe_ref}%")
            return ab if ab

            return nil
          end

          return ArticleBill.where(partner_slug: partner_slug).order(created_at: :desc).first
        end
      end
    end

    ab = ArticleBill.find_by(article_url: key)
    return nil if bill_id_int.present? && ab&.bill_id != bill_id_int

    ab
  end

  def self.pro_stance?(stance_str)
    stance_str.in?(%w[FOR PRO SUPPORT YES TRUE])
  end

  def self.con_stance?(stance_str)
    stance_str.in?(%w[AGAINST CON OPPOSE NO FALSE])
  end
end
