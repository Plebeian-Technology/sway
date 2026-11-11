# frozen_string_literal: true

# @lat: [[surfaces#Dual-rendered JSON]]
module MobileFormatNegotiation
  extend ActiveSupport::Concern

  # @lat: [[lazy-inertia-props#Mobile JSON omission is an explicit request]]
  def render_inertia_or_json(page:, props:)
    if mobile_api_request?
      vary_json_omission_header
      render json: resolve_inertia_props(props)
    else
      render inertia: page, props: props
    end
  end

  # @lat: [[surfaces#Dual-rendered JSON]]
  def redirect_or_json(path, flash_message: nil, status: :found)
    if mobile_api_request?
      render json: {redirect: path, flash: flash_message}.compact
    else
      redirect_to path, notice: flash_message, status: status
    end
  end

  def mobile_api_request?
    bearer_authorization_header? || request.format.json?
  end

  def resolve_inertia_props(props)
    if props.is_a?(Hash)
      requested = requested_optional_prop_names
      props = props.reject do |key, value|
        requested.include?(key.to_s) && value.is_a?(InertiaRails::OptionalProp)
      end
    end
    resolve_inertia_prop_value(props)
  end

  def requested_optional_prop_names
    header = request.headers["X-Sway-Omit-Props"]
    return [] unless header.is_a?(String)

    header.split(",").map(&:strip).select { |name| OMITTABLE_OPTIONAL_PROPS.include?(name) }.uniq
  end

  def vary_json_omission_header
    vary = response.headers["Vary"].to_s.split(",").map(&:strip).compact_blank
    return if vary.any? { |token| token.casecmp("X-Sway-Omit-Props").zero? }

    response.headers["Vary"] = (vary + ["X-Sway-Omit-Props"]).join(", ")
  end

  def resolve_inertia_prop_value(props)
    acc_init = {}
    # @type var acc_init: Hash[untyped, untyped]
    case props
    when Hash
      props.each_with_object(acc_init) { |(k, v), acc| acc[k] = resolve_inertia_prop_value(v) }
    when InertiaRails::BaseProp
      resolve_inertia_prop_value(props.call(self))
    when Proc
      # @lat: [[lazy-inertia-props#Why the props became callables]]
      # steep:ignore:start
      resolve_inertia_prop_value(instance_exec(&props))
      # steep:ignore:end
    else
      props
    end
  end

  # @lat: [[identity-and-access#Identity and access#Sessions, cookies and bearer tokens]]
  def bearer_authorization_header?
    /\A(?:Bearer|Token)\s+\S/i.match?(request.headers["Authorization"].to_s)
  end

  OMITTABLE_OPTIONAL_PROPS = %w[legislators legislator_votes districts public_testimony_letters].freeze
end
