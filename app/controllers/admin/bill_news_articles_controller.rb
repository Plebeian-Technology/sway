# frozen_string_literal: true

module Admin
  # @lat: [[news-article-evidence#Article identity and bill association]]
  class BillNewsArticlesController < ApplicationController
    before_action :verify_is_sway_admin
    before_action :set_bill
    before_action :set_bill_news_article, only: %i[update]

    rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

    def index
      articles = @bill.bill_news_articles
        .includes(:news_article, :current_text_version, :approved_by, :stance_by)
        .order(created_at: :desc)

      render json: AdminBillNewsArticleResource.new(articles).serializable_hash
    end

    def create
      discovery_request = find_discovery_request
      receipt = BillNewsArticleFetchService.call(
        bill: @bill,
        requested_by: current_user,
        **{discovery_request: discovery_request}.compact
      )

      if receipt&.status == "succeeded"
        @bill.bill_news_articles.where(current_text_version_id: nil).find_each do |bna|
          NewsArticleTextFetchJob.perform_later(bna.id)
        end
      end

      if request.inertia?
        if receipt&.status == "failed"
          error_message = extract_receipt_error(receipt) || "Failed to retrieve news articles."
          redirect_back_or_to summary_bill_creator_path(@bill), status: :see_other, inertia: {errors: {news_article: error_message}}
        else
          redirect_back_or_to summary_bill_creator_path(@bill), status: :see_other
        end
      else
        articles = @bill.bill_news_articles
          .includes(:news_article, :current_text_version, :approved_by, :stance_by)
          .order(created_at: :desc)
        serialized = AdminBillNewsArticleResource.new(articles).serializable_hash

        status_code = (receipt&.status == "failed") ? :unprocessable_content : :ok

        body = {receipt_status: receipt&.status, articles: serialized}
        body[:error] = extract_receipt_error(receipt) if status_code == :unprocessable_content
        render json: body, status: status_code
      end
    end

    def update
      result = ReviewBillNewsArticleService.call(
        bill: @bill,
        bill_news_article: @bill_news_article,
        admin: current_user,
        params: article_params
      )

      if request.inertia?
        redirect_back_or_to summary_bill_creator_path(@bill), status: :see_other
      else
        render json: AdminBillNewsArticleResource.new(result.bill_news_article).serializable_hash, status: :ok
      end
    rescue ArgumentError, ActiveRecord::RecordInvalid, ActionController::ParameterMissing => e
      if request.inertia?
        redirect_back_or_to summary_bill_creator_path(@bill), status: :see_other, inertia: {errors: {news_article: e.message}}
      else
        render json: {error: e.message}, status: :unprocessable_content
      end
    end

    private

    def extract_receipt_error(receipt)
      return nil unless receipt&.status == "failed" && receipt.respond_to?(:diagnostics)

      Array(receipt.diagnostics).reverse_each do |entry|
        next unless entry.is_a?(Hash)

        err = (entry["error"] || entry[:error]).to_s.strip
        return err if err.present?
      end

      nil
    end

    def record_not_found
      if request.inertia?
        redirect_back_or_to root_path, alert: "Not found"
      else
        render json: {error: "Not found"}, status: :not_found
      end
    end

    def set_bill
      @bill = Bill.find(params[:bill_id])
    end

    def set_bill_news_article
      @bill_news_article = @bill.bill_news_articles.find(params[:id])
    end

    def find_discovery_request
      req_id = params[:discovery_request_id] || params.dig(:bill_news_article, :discovery_request_id)
      return nil if req_id.blank?

      @bill.news_article_discovery_requests.find_by!(id: req_id, requested_by: current_user)
    end

    def article_params
      if params.key?(:bill_news_article)
        nested = params[:bill_news_article]
        if nested.is_a?(ActionController::Parameters)
          nested.permit(:approved, :stance, :article_kind, :text)
        elsif nested.is_a?(Hash)
          ActionController::Parameters.new(nested).permit(:approved, :stance, :article_kind, :text)
        else
          ActionController::Parameters.new.permit(:approved, :stance, :article_kind, :text)
        end
      else
        params.permit(:approved, :stance, :article_kind, :text)
      end
    end
  end
end
