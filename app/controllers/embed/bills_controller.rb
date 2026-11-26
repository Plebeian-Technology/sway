# frozen_string_literal: true

# @lat: [[embeddable-bill-widget#Embeddable bill widget#Controller implementation]]
module Embed
  class BillsController < BaseController
    PAYLOAD_VERSION = "4"

    def show
      @bill = Bill.find(params[:id])

      response.headers["Cache-Control"] = "public, max-age=60, s-maxage=300, stale-while-revalidate=600"
      response.headers["Vary"] = "Accept, X-Inertia"
      response.headers.delete("X-Frame-Options")

      fresh_when(
        etag: [PAYLOAD_VERSION, @bill, @bill.bill_score, referral_params, request.headers["X-Inertia"].present?],
        public: true
      )
      return if performed?

      serialized = EmbedBillResource.new(@bill, params: referral_params).serializable_hash #: Hash[String, untyped]
      render inertia: Pages::EMBED_BILL, props: {
        bill: serialized,
        cta_url: serialized["cta_url"]
      }
    end

    private

    def referral_params
      request.query_parameters.select do |k, v|
        (k == "partner" || k == "ref" || k.start_with?("utm_")) && v.present?
      end.sort.to_h
    end
  end
end
