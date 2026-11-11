# frozen_string_literal: true

# @lat: [[bill-creator-run-pin-redirect-interceptor#Why a refusal's error messages are pinned alongside the run pin]]
module BillCreatorRunPinRedirects
  extend ActiveSupport::Concern

  BILL_CREATOR_PREFIX = "/admin/bill_creator"
  RUN_PIN_PARAM = "run_id"

  # @lat: [[bill-creator-run-pin-redirect-interceptor#Why this is one interceptor and not a change at each redirect]]
  def _compute_redirect_to_location(request, options)
    carry_pinned_run(super)
  end

  private

  def carry_pinned_run(location)
    return location unless location.is_a?(String)

    target = bill_creator_uri(location)
    return location if target.nil?

    query = decode_query(target.query.to_s)
    return location if query.key?(RUN_PIN_PARAM)

    pin = pinned_run_id_from_referer
    return location if pin.nil?
    return location unless same_bill?(target.path, referer_uri&.path)

    query[RUN_PIN_PARAM] = pin
    target.query = URI.encode_www_form(query)
    target.to_s
  end

  # @lat: [[bill-creator-run-pin-redirect-interceptor#Where the pin is read from, and why it is not the request]]
  def pinned_run_id_from_referer
    referer = referer_uri
    return nil if referer.nil?

    value = decode_query(referer.query.to_s)[RUN_PIN_PARAM].to_s
    value.match?(/\A\d+\z/) ? value : nil
  end

  # @lat: [[bill-creator-run-pin-redirect-interceptor#Where the pin is read from, and why it is not the request]]
  def referer_uri
    return @referer_uri if defined?(@referer_uri)

    same_origin = url_from(request.referer)
    @referer_uri = same_origin ? URI.parse(same_origin) : nil
  rescue URI::InvalidURIError
    @referer_uri = nil
  end

  def bill_creator_uri(location)
    uri = URI.parse(location)
    return nil unless uri.host.nil? || uri.host == request.host
    return nil unless uri.path.to_s.start_with?(BILL_CREATOR_PREFIX)

    uri
  rescue URI::InvalidURIError
    nil
  end

  # @lat: [[bill-creator-run-pin-redirect-interceptor#Why a refusal's error messages are pinned alongside the run pin]]
  def decode_query(query)
    return {} if query.empty?

    URI.decode_www_form(query).to_h
  rescue ArgumentError
    {}
  end

  # @lat: [[bill-creator-run-pin-redirect-interceptor#Why it refuses to cross bills]]
  def bill_id_in_path(path)
    segment = path.to_s.delete_prefix(BILL_CREATOR_PREFIX).split("/")[1]
    segment.to_s.match?(/\A\d+\z/) ? segment : nil
  end

  def same_bill?(target_path, referer_path)
    return false if referer_path.nil?

    left = bill_id_in_path(target_path)
    !left.nil? && left == bill_id_in_path(referer_path)
  end
end
