# frozen_string_literal: true

require "uri"
require_relative "../../../lib/query_parameter_check"
require_relative "../../../lib/navigation_route_exclusions"

# @lat: [[query-parameter-navigation-carry#Query parameter navigation carry#Centralized interception mechanism#Server redirect carry follows real form writes]]
module QueryParameterRedirectCarry
  extend ActiveSupport::Concern

  INTENTIONAL_EMPTY_LIST_PARAMETERS = %w[selected_stages stages].freeze
  BILL_CREATOR_ID_PATHS = [
    %r{\A/admin/bill_creator/(\d+)(?:/|\z)},
    %r{\A/bills/(\d+)/edit(?:/|\z)}
  ].freeze

  included do
    after_action :carry_query_parameters_across_redirect
  end

  private

  def carry_query_parameters_across_redirect
    return unless [301, 302, 303, 307, 308].include?(response.status)
    return if NavigationRouteExclusions.excluded_path?(request.path)

    target = same_origin_redirect_uri(response.location)
    return unless target
    return if NavigationRouteExclusions.excluded_path?(target.path)

    source = same_origin_referer_uri
    check = QueryParameterCheck.new(Rails.root.to_s)
    return unless check.offences.empty?

    source_path = (request.get? || request.head?) ? request.path : source&.path
    source_feature = source_path && check.feature_for_path(source_path)
    target_feature = check.feature_for_path(target.path)
    target_pairs = raw_query_pairs(target.query)
    original_target_pairs = target_pairs
    source_pairs = raw_query_pairs(request.query_string)
    target_names = target_pairs.pluck(:name)
    normalized_target_names = target_names.map { |name| name.delete_suffix("[]") }
    carried_pairs = eligible_redirect_pairs(
      check,
      source_feature,
      target_feature,
      source_path,
      target,
      source_pairs,
      normalized_target_names
    )

    cleared_target_names = first_empty_ordinary_names(target_pairs, check, target_feature)
    target_pairs = target_pairs.reject do |pair|
      cleared_target_names.include?(pair[:name])
    end
    combined = target_pairs + carried_pairs
    return if combined.length == original_target_pairs.length && carried_pairs.empty?

    target.query = combined.pluck(:raw).join("&").presence
    response.location = target.to_s
  rescue URI::InvalidURIError
    nil
  end

  def eligible_redirect_pairs(check, source_feature, target_feature, source_path, target, source_pairs, target_names)
    allowed_names = check.global_ambient.dup
    if source_feature && source_feature == target_feature && !cross_bills_surface_redirect?(source_feature, source_path, target.path)
      source_registry = check.features.fetch(source_feature)
      allowed_names.concat(source_registry[:parameters])
      allowed_names.concat(source_registry[:legacy_aliases])
      if past_bills_of_the_month_path?(target.path)
        allowed_names.delete("bills_legislative_session_id")
        allowed_names.delete("legislative_session_id")
      end
    end

    run_id_pairs = source_pairs.select { |pair| pair[:name] == "run_id" }
    allowed_names.delete("run_id")
    if valid_same_bill_run_pin?(source_feature, target_feature, source_path, target.path, run_id_pairs, target_names)
      allowed_names << "run_id"
    end

    cleared_source_names = first_empty_ordinary_names(source_pairs, check, source_feature)
    source_pairs.select do |pair|
      parameter_name = pair[:name].delete_suffix("[]")
      allowed = allowed_names.include?(pair[:name]) ||
        INTENTIONAL_EMPTY_LIST_PARAMETERS.include?(parameter_name) && allowed_names.include?(parameter_name)
      next false unless allowed
      next false if cleared_source_names.include?(pair[:name])
      next false if target_names.include?(parameter_name)

      family = target_feature && check.parameter_family(target_feature, parameter_name)
      next false if family.present? && (family & target_names).any?
      true
    end
  end

  def valid_same_bill_run_pin?(source_feature, target_feature, source_path, target_path, run_id_pairs, target_names)
    return false unless run_id_pairs.one?
    return false unless run_id_pairs.first[:value].match?(/\A\d+\z/)
    return false unless source_feature == "bill_creator" && target_feature == "bill_creator"
    return false if target_names.include?("run_id")

    source_id = bill_creator_bill_id(source_path)
    target_id = bill_creator_bill_id(target_path)
    source_id.present? && source_id == target_id
  end

  def past_bills_of_the_month_path?(path)
    path.to_s.start_with?("/past_bills_of_the_month")
  end

  def cross_bills_surface_redirect?(feature_name, source_path, target_path)
    return false unless feature_name == "bills" && source_path.present?

    past_bills_of_the_month_path?(source_path) != past_bills_of_the_month_path?(target_path)
  end

  def bill_creator_bill_id(path)
    BILL_CREATOR_ID_PATHS.each do |pattern|
      match = pattern.match(path.to_s)
      return match[1] if match
    end

    nil
  end

  def first_empty_ordinary_names(pairs, check, feature_name)
    pairs.group_by { |pair| pair[:name] }.filter_map do |name, values|
      next if values.first[:value].present?
      next if INTENTIONAL_EMPTY_LIST_PARAMETERS.include?(name.delete_suffix("[]"))
      next unless registered_target_name?(name, check, feature_name)

      name
    end
  end

  def registered_target_name?(name, check, feature_name)
    check.global_ambient.include?(name) ||
      (!feature_name.nil? && !check.parameter_family(feature_name, name).empty?)
  end

  def same_origin_redirect_uri(location)
    return nil unless location.is_a?(String) && location.present?

    uri = URI.parse(location)
    if uri.host.nil? && uri.scheme.nil?
      return nil unless location.start_with?("/") && !location.start_with?("//")

      uri = URI.join("#{request.base_url}/", location)
    end
    return nil unless same_origin_uri?(uri)

    uri
  end

  def same_origin_referer_uri
    referer = request.referer
    return nil if referer.blank?

    uri = URI.parse(referer)
    same_origin_uri?(uri) ? uri : nil
  rescue URI::InvalidURIError
    nil
  end

  def same_origin_uri?(uri)
    request_uri = URI.parse(request.base_url)
    return false unless uri.userinfo.nil? && uri.scheme && uri.host

    !!(
      uri.scheme.casecmp?(request_uri.scheme) &&
        uri.host.casecmp?(request_uri.host) &&
        uri.port == request_uri.port
    )
  end

  def raw_query_pairs(query)
    return [] if query.blank?

    query.split("&", -1).filter_map do |raw|
      next if raw.empty?

      raw_name, raw_value = raw.split("=", 2)
      next if raw_name.nil?

      {
        raw: raw,
        name: URI.decode_www_form_component(raw_name),
        value: URI.decode_www_form_component(raw_value.to_s)
      }
    end
  rescue ArgumentError
    []
  end
end
