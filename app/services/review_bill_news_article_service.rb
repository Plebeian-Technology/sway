# frozen_string_literal: true

# @lat: [[news-article-evidence#Article identity and bill association]]
# @lat: [[news-article-evidence#Immutable article text]]
# @lat: [[news-review#Admin article review actions]]
class ReviewBillNewsArticleService
  class Result
    delegate_missing_to :bill_news_article

    attr_reader :status, :bill_news_article, :errors

    def initialize(status:, bill_news_article:, errors: [])
      @status = status
      @bill_news_article = bill_news_article
      @errors = errors
    end

    def ok?
      status == :ok
    end

    def success?
      status == :ok
    end
  end

  def self.call(bill:, bill_news_article:, admin: nil, actor: nil, params: {})
    new(bill: bill, bill_news_article: bill_news_article, admin: admin, actor: actor, params: params).call
  end

  def initialize(bill:, bill_news_article:, admin: nil, actor: nil, params: {})
    @bill = bill
    @bill_news_article = bill_news_article
    @admin = admin || actor
    @params = params.is_a?(ActionController::Parameters) ? params.permit!.to_h.symbolize_keys : params.to_h.symbolize_keys
  end

  def call
    validate_actor_and_bill!

    ActiveRecord::Base.transaction do
      apply_article_kind_update!
      new_text_version = apply_manual_text!
      withdrew_approval = apply_approval_update!
      apply_stance_update!
      apply_evidence_retraction!(new_text_version: new_text_version, withdrew_approval: withdrew_approval)
    end

    Result.new(status: :ok, bill_news_article: bill_news_article.reload)
  end

  private

  attr_reader :bill, :bill_news_article, :admin, :params

  def validate_actor_and_bill!
    raise ArgumentError, "admin must be a Sway admin" unless admin.is_a?(User) && admin.respond_to?(:is_sway_admin?) && admin.is_sway_admin?
    raise ArgumentError, "bill must be a persisted Bill" unless bill.is_a?(Bill) && bill.persisted?
    raise ArgumentError, "bill_news_article must be a persisted BillNewsArticle" unless bill_news_article.is_a?(BillNewsArticle) && bill_news_article.persisted?
    raise ArgumentError, "bill_news_article does not belong to the specified bill" unless bill_news_article.bill_id == bill.id
  end

  def apply_article_kind_update!
    return unless params.key?(:article_kind) && params[:article_kind].present?

    bill_news_article.news_article.update!(article_kind: params[:article_kind])
  end

  def apply_manual_text!
    return unless params.key?(:text)

    raw_text = params[:text].to_s.strip
    return if raw_text.blank?

    text_version = NewsArticleTextVersion.create!(
      news_article: bill_news_article.news_article,
      origin: "manual",
      extraction_status: "extracted",
      text: raw_text,
      actor: admin,
      requested_url: bill_news_article.news_article.canonical_url,
      final_url: bill_news_article.news_article.canonical_url
    )

    bill_news_article.current_text_version = text_version
    bill_news_article.review_version += 1
    bill_news_article.save!

    text_version
  end

  def apply_approval_update!
    return false unless params.key?(:approved)

    target_approved = ActiveModel::Type::Boolean.new.cast(params[:approved])
    return false if target_approved == bill_news_article.approved

    if target_approved
      bill_news_article.approve!(by: admin)
      false
    else
      bill_news_article.withdraw_approval!(by: admin)
      true
    end
  end

  # @lat: [[evidence-retraction-writers#ReviewBillNewsArticleService, news article text or approval changes]]
  def apply_evidence_retraction!(new_text_version:, withdrew_approval:)
    return unless withdrew_approval || new_text_version.present?

    provisioning = bill.bill_llm_provisioning
    return unless provisioning
    return if provisioning.draft_org_positions.blank?

    provisioning.with_lock do
      drafts = provisioning.draft_org_positions
      if drafts.is_a?(::Array) && drafts.any?
        active_text_version_id = (bill_news_article.approved? && !withdrew_approval) ? new_text_version&.id : nil
        retracted = BillLlmProvisioning.drafts_with_news_evidence_retracted(
          drafts,
          bill_news_article_id: bill_news_article.id,
          text_version_id: active_text_version_id
        )

        provisioning.update!(draft_org_positions: retracted) if retracted != drafts
      end
    end
  end

  def apply_stance_update!
    return unless params.key?(:stance)

    raw_stance = params[:stance].presence
    if raw_stance.nil?
      if bill_news_article.stance.present?
        bill_news_article.clear_stance!(by: admin)
      end
    else
      stance_str = raw_stance.to_s
      raise ArgumentError, "Invalid stance: #{raw_stance}" unless BillNewsArticle::STANCES.include?(stance_str)

      if bill_news_article.stance != stance_str
        bill_news_article.set_stance!(stance_str, by: admin)
      end
    end
  end
end
