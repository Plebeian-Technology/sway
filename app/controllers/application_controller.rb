# frozen_string_literal: true

require_relative "../../lib/sway/sql_query_telemetry"

class ApplicationController < ActionController::Base
  include DefaultMetaTaggable
  include RelyingParty
  include ApiKeyAuthenticatable
  include MobileFormatNegotiation
  include Pages
  include RateLimitResponder
  include JsonErrorRenderable
  include BillCreatorRunPinRedirects
  include QueryParameterRedirectCarry
  include ThemeHelper

  # @lat: [[identity-and-access#Identity and access#The rate limit store swaps in after boot]]
  class SwappableCacheStore
    def initialize(backend)
      @backend = backend
    end

    attr_writer :backend

    def method_missing(name, ...)
      @backend.public_send(name, ...)
    end

    def respond_to_missing?(name, include_private = false)
      @backend.respond_to?(name, include_private) || super
    end
  end

  RATE_LIMIT_STORE = SwappableCacheStore.new(ActiveSupport::Cache::NullStore.new)

  rate_limit(to: 1000, within: 1.minute, by: -> { request.remote_ip }, store: RATE_LIMIT_STORE)

  rescue_from ActionController::InvalidAuthenticityToken,
    with: :inertia_page_expired_error

  protect_from_forgery with: :exception, prepend: true

  # @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
  skip_forgery_protection if: :authenticated_bearer_request?

  # @lat: [[activity-log-flash-transport#Why the current request is held in Current]]
  before_action { Current.request = request }

  around_action :track_sql_query_telemetry, prepend: true

  before_action :reject_js_request_format
  before_action :is_api_request_and_is_route_api_accessible?
  before_action :authenticate_sway_user!
  before_action :set_sway_locale_id_in_session
  before_action :capture_attribution_param

  after_action :add_rsl_license_header
  after_action :forbid_storing_a_one_time_secret
  after_action :mark_authenticated_response_private

  # @lat: [[identity-and-access#The one response whose body carries a secret is never stored]]
  ONE_TIME_SECRET_FLASH_KEYS = %w[new_api_key_token].freeze

  # @lat: [[client-caches-and-identity#What the page cache is allowed to hold]]
  PRIVATE_CACHE_CONTROL = "max-age=0, private, must-revalidate"

  helper_method :current_user,
    :current_sway_locale,
    :verify_is_sway_admin,
    :invited_by_id,
    :theme_preference,
    :theme_html_class,
    :theme_id,
    :theme_font_stylesheet_href,
    :current_visitor_token,
    :current_attribution_key

  inertia_share flash: -> { flash_with_id }

  inertia_share do
    {
      user: -> do
        # @lat: [[identity-and-access#User JSON exposes only selected fields#Shared address props use an explicit field list]]
        current_user&.to_sway_json&.merge(
          {address: current_user&.address&.to_sway_json}
        )
      end,
      sway_locale: -> { current_sway_locale&.to_sway_json },
      # @lat: [[identity-and-access#User JSON exposes only selected fields#Locale props are never cached once per browser]]
      sway_locales: -> { locales_for_current_user.map(&:to_sway_json) },
      # @lat: [[identity-and-access#User JSON exposes only selected fields#Locale props are never cached once per browser]]
      sway_locale_options: -> { locales_for_current_user.map(&:to_select_option) },
      # @lat: [[identity-and-access#User JSON exposes only selected fields#Locale props are never cached once per browser]]
      # @lat: [[admin-locales-registration-visibility#Why admin authoring and prompt previews scope to declared locales]]
      admin_sway_locale_options: -> { current_user&.is_sway_admin? ? SwayLocale.declared.map(&:to_select_option) : nil },
      legislator_photo_urls: -> { current_user_legislator_photo_urls },
      # @lat: [[theme-font-hrefs#Why the shared theme prop runs in an instance context]]
      # @lat: [[theme-font-hrefs#Why the shared theme prop carries the whole font map]]
      theme: -> { {preference: theme_preference, id: theme_id, font_hrefs: ThemeHelper::THEME_FONT_HREFS} }, # steep:ignore
      # @lat: [[release-shared-prop#The release prop is shared across pages]]
      release: -> { Sway::Release.to_sway_json },
      reassignment_notifications: -> do
        pending_representative_reassignments_prop
      end,
      representative_reassignments: -> do
        pending_representative_reassignments_prop
      end,
      # @lat: [[shared-error-params#Raw error parameters never reach shared page props]]
      params: {
        sway_locale_id: params[:sway_locale_id]
      },
      # @lat: [[low-friction-voting#Provisional vote capture and cookie lifecycle]]
      pending_vote: -> do
        pv = cookies.encrypted[:sway_pending_vote]
        if pv.is_a?(String)
          begin
            pv = JSON.parse(pv)
          rescue JSON::ParserError
            pv = nil
          end
        end
        if pv.is_a?(Hash)
          bill_id = pv["bill_id"] || pv[:bill_id]
          support = pv["support"] || pv[:support]
          if bill_id.present? && support.present?
            {"bill_id" => bill_id.to_i, "support" => support.to_s}
          end
        end
      end
    }
  end

  # @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
  def sign_in(user)
    invited_by_id_before_reset = invited_by_id
    attribution_key_before_reset = cookies[:sway_attribution_key]
    visitor_token_before_reset = cookies[:sway_visitor_token]

    # @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
    reset_session

    cookies.permanent[UserInviteLink::INVITED_BY_SESSION_KEY] = invited_by_id_before_reset
    cookies.permanent[:sway_attribution_key] = attribution_key_before_reset if attribution_key_before_reset.present?
    cookies.permanent[:sway_visitor_token] = visitor_token_before_reset if visitor_token_before_reset.present?

    begin
      cookies.encrypted[:refresh_token] = RefreshToken.for(
        user,
        request
      ).as_cookie
      session[:user_id] = user.id
      reset_user_memoization(user)
      # @lat: [[client-caches-and-identity#Identity changes wait for network-only pages]]
      session[:inertia_clear_history] = true
      # @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
      session[:auth_identity] = user.created_at&.to_i

      user.sign_in_count = user.sign_in_count + 1
      user.last_sign_in_at = user.current_sign_in_at
      user.current_sign_in_at = Time.zone.now
      user.last_sign_in_ip = user.current_sign_in_ip
      user.current_sign_in_ip = request.remote_ip
      # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#Sign-in counter failure is logged, not raised]]
      unless user.save
        SwayLogging.info(
          "sign_in.counter_update_failed",
          user_id: user.id,
          errors: user.errors.full_messages
        )
      end

      if user.registered?
        user.complete! unless user.registration_status == "completed" && user.is_registration_complete
        cookies.permanent[
          :sway_locale_id
        ] = user.default_sway_locale&.id
      end
    rescue => e
      SwayLogging.log_exception(
        "application.sign_in_failed",
        exception: e,
        user_id: user.id,
        remote_ip: request.remote_ip
      )
      reset_session
      cookies.clear
      reset_user_memoization(nil)
      raise e
    end
  end

  def sign_out
    user = current_user
    raw_cookie = cookies.encrypted[:refresh_token]
    raw_token = raw_cookie.is_a?(Hash) ? (raw_cookie[:value] || raw_cookie["value"]) : raw_cookie
    RefreshToken.where(token: raw_token.to_s).delete_all if raw_token.present?
    RefreshToken.where(user_id: user.id).delete_all if user
    ActionCable.server.remote_connections.where(current_user: user).disconnect if user
    reset_session
    cookies.clear
    reset_user_memoization(nil)
  end

  def authenticated_bearer_request?
    bearer_authorization_header? && authenticate_with_api_key.present?
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = if token_credential_supplied?
      authenticate_with_api_key
    else
      authenticate_with_cookies
    end
  end

  def current_sway_locale
    return @current_sway_locale if defined?(@current_sway_locale)

    @current_sway_locale = find_current_sway_locale
  end

  def invited_by_id
    value = cookies.permanent[UserInviteLink::INVITED_BY_SESSION_KEY]
    # @lat: [[inviter-id-logging#Lookup logs presence only]]
    SwayLogging.info("invited_by_id.lookup", invited: value.present?)
    value
  end

  def authenticate_with_cookies
    u = User.find_by(id: session[:user_id]) if session[:user_id].present?

    # @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
    if u && session[:auth_identity].present? && session[:auth_identity].to_i != u.created_at.to_i
      SwayLogging.info("authenticate_with_cookies.stale_session_identity", user_id: u.id)
      session.delete(:user_id)
      session.delete(:auth_identity)
      u = nil
    end

    if u.nil? && cookies.encrypted[:refresh_token].present?
      current_refresh_token =
        RefreshToken.find_by(token: cookies.encrypted[:refresh_token])

      if current_refresh_token&.usable_for?(request)
        SwayLogging.info("authenticate_with_cookies.refresh_token")
        u = current_refresh_token.user
        if u.present?
          session[:user_id] = u.id
          # @lat: [[client-caches-and-identity#Identity changes wait for network-only pages]]
          session[:inertia_clear_history] = true
          session[:auth_identity] = u.created_at&.to_i
          cookies.encrypted[:refresh_token] = RefreshToken.for(
            u,
            request
          ).as_cookie
        end
      end
    end

    # @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
    session[:auth_identity] = u.created_at&.to_i if u && session[:auth_identity].blank?

    u
  end

  def is_api_request_and_is_route_api_accessible?
    return unless request.path.starts_with?("/api/")

    # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#Missing API credentials stop before the admin decision]]
    authenticate_with_api_key!
    return if performed?

    return unless request.path.starts_with?("/api/admin/")
    return if current_user&.is_sway_admin?

    SwayLogging.warn(
      "application.api_request_unauthorized",
      path: request.path,
      method: request.request_method,
      admin_namespace: true,
      user_id: current_user&.id,
      remote_ip: request.remote_ip
    )
    render json: {
             message:
               "This API key does not belong to a Sway admin."
           },
      status: :unauthorized
  end

  def authenticate_sway_user!
    u = current_user
    if u.nil?
      SwayLogging.info "No current user, redirect to root path"
      if request.format.json?
        render_error(code: "unauthenticated", message: "Sign in to continue.", status: :unauthorized)
      else
        flash[:notice] = "Sign up or sign in to view this page."
        redirect_back_or_to(root_url)
      end
    elsif u.registered?
      u.complete! unless u.completed? && u.is_registration_complete
    elsif request.format.json?
      render_error(code: "registration_incomplete", message: "Finish registration to continue.", status: :forbidden)
    else
      SwayLogging.info "Current user registration is not complete, redirect to sway registration"
      flash[:notice] = "Sign up or sign in to view this page."
      redirect_to sway_registration_index_path
    end
  end

  # @lat: [[identity-and-access#The admin gate is a lint rule]]
  def verify_is_sway_admin
    return if current_user&.is_sway_admin?

    # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#The Sway admin gate has two refusal shapes]]
    if mobile_api_request?
      render_error(code: "forbidden", message: "Admin access required.", status: :forbidden)
    else
      redirect_to root_path
    end
  end

  private

  def reset_user_memoization(user)
    @current_user = user
    remove_instance_variable(:@current_sway_locale) if defined?(@current_sway_locale)
    remove_instance_variable(:@locales_for_current_user) if defined?(@locales_for_current_user)
    if defined?(@pending_representative_reassignments_prop)
      remove_instance_variable(:@pending_representative_reassignments_prop)
    end
  end

  # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
  def bill_creator_tab_param(source = params)
    source.key?(:bill_creator_tab) ? source[:bill_creator_tab] : source[:tab_key]
  end

  def pending_representative_reassignments_prop
    return @pending_representative_reassignments_prop if defined?(@pending_representative_reassignments_prop)

    @pending_representative_reassignments_prop =
      if current_user
        RepresentativeReassignmentResource.new(
          current_user
            .representative_reassignments
            .pending_in_app
            .includes(
              :district,
              :previous_district,
              legislator: [
                {photo_attachment: :blob},
                {active_term: {district: :sway_locale}},
                {legislator_terms: [:seat, {district: :sway_locale}, :legislator_district_scores, :legislator_locale_scores]}
              ],
              previous_legislator: [
                {photo_attachment: :blob},
                {active_term: {district: :sway_locale}},
                {legislator_terms: [:seat, {district: :sway_locale}, :legislator_district_scores, :legislator_locale_scores]}
              ]
            )
        ).serializable_hash
      else
        []
      end
  end

  # @lat: [[request-locale-selection#A query locale is validated before the cookie is written]]
  def set_sway_locale_id_in_session
    requested_id = params[:sway_locale_id].presence
    return if requested_id.blank?

    if requested_sway_locale.nil?
      SwayLogging.warn(
        "sway_locale.unresolvable_id_refused",
        requested_sway_locale_id: requested_id.to_s[0, 100],
        message: "the address named a jurisdiction that does not exist; the cookie was left alone"
      )
      flash.now[:alert] = "That jurisdiction could not be found, so nothing was changed. " \
        "You are seeing #{current_sway_locale&.name.presence || "the default jurisdiction"}."
      return
    end

    cookies.permanent[:sway_locale_id] = requested_sway_locale&.id
  end

  # @lat: [[request-locale-selection#One request reuses its locale lookup]]
  def requested_sway_locale
    return @requested_sway_locale if defined?(@requested_sway_locale)

    requested_id = params[:sway_locale_id].presence
    @requested_sway_locale = requested_id && SwayLocale.find_by(id: requested_id)
  end

  # @lat: [[identity-and-access#User JSON exposes only selected fields#Locale props are never cached once per browser]]
  # @lat: [[request-locale-selection#Anonymous fallback locale lists are filtered to declared locales]]
  def locales_for_current_user
    @locales_for_current_user ||= begin
      user_locales = current_user&.sway_locales
      locales = (user_locales.presence || SwayLocale.declared).to_a
      if locales.present?
        ActiveRecord::Associations::Preloader.new(
          records: locales,
          associations: :current_legislative_session
        ).call
      end
      locales
    end
  end

  def find_current_sway_locale
    # @lat: [[request-locale-selection#The query locale wins over the cookie on reads]]
    return requested_sway_locale if requested_sway_locale

    stored_id = cookies.permanent[:sway_locale_id].presence
    from_cookie = stored_id && SwayLocale.find_by(id: stored_id)

    # @lat: [[request-locale-selection#A stale locale cookie is removed]]
    cookies.delete(:sway_locale_id) if stored_id && from_cookie.nil?

    from_cookie ||
      # @lat: [[locale-name-is-derived#A shared locale slug is parsed into its name parts]]
      SwayLocale.find_by_name_parts(params[:sway_locale_name]) || # rubocop:disable Rails/DynamicFindBy
      current_user&.default_sway_locale || SwayLocale.default_locale
  end

  # @lat: [[legislator-photo-prefetch#Prefetching a reader's own legislator photos]]
  # @lat: [[legislator-photo-prefetch#Why the candidate set is narrowed before the term filter runs]]
  def current_user_legislator_photo_urls
    user = current_user
    locale_id = current_sway_locale&.id
    return [] if user.nil? || locale_id.nil?

    candidate_ids = own_active_legislator_ids(user, locale_id)
    return [] if candidate_ids.empty?

    photo_urls_for(LegislatorTerm.current_for(candidate_ids).pluck(:legislator_id))
  end

  def own_active_legislator_ids(user, locale_id)
    Legislator
      .where(id: user.user_legislators.where(active: true).select(:legislator_id))
      .where(sway_locale_id: locale_id)
      .pluck(:id)
  end

  def photo_urls_for(legislator_ids)
    Legislator
      .where(id: legislator_ids)
      .preload(photo_attachment: :blob)
      .filter_map do |legislator|
        MirroredAssetUrl.for(legislator.photo, fallback: legislator.photo_url).presence
      end
  end

  # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#A refused CSRF write leaves a fresh retry path]]
  def inertia_page_expired_error
    flash[:page_expired] = true
    redirect_back_or_to(
      "/",
      allow_other_host: false,
      alert: "The page expired, please try again."
    )
  end

  def add_rsl_license_header
    response.set_header(
      "Link",
      '<https://sway.vote/license.xml>; rel="license"; type="application/rsl+xml"'
    )
  end

  # @lat: [[identity-and-access#The one response whose body carries a secret is never stored]]
  def forbid_storing_a_one_time_secret
    return if flash.to_hash.keys.none? { |key| ONE_TIME_SECRET_FLASH_KEYS.include?(key.to_s) }

    response.headers["Cache-Control"] = "no-store"
  end

  # @lat: [[toasts#Flash toast dedupe]]
  def flash_with_id
    hash = flash.to_hash
    return hash if hash.empty? || request.request_id.blank?

    hash.merge("id" => request.request_id)
  end

  def mark_authenticated_response_private
    return if response.headers["Cache-Control"].present?
    return if current_user.blank?

    response.headers["Cache-Control"] = PRIVATE_CACHE_CONTROL
  end

  def append_info_to_payload(payload)
    super

    payload[:request_id] = request.request_id
    payload[:remote_ip] = request.remote_ip
    payload[:user_agent] = request.user_agent
    payload[:user_id] = current_user&.id
    payload[:sway_locale_id] = @current_sway_locale&.id if defined?(@current_sway_locale)
    payload[:api_request] = request.path.start_with?("/api/")
    payload[:inertia] = request.headers["X-Inertia"] == "true"
    payload[:inertia_partial_component] = request.headers[
      "X-Inertia-Partial-Component"
    ]
    if (telemetry = @sql_query_telemetry)
      payload[:sql_queries_count] = telemetry.queries
      payload[:sql_cached_queries_count] = telemetry.cached_queries
      payload[:sql_max_fingerprint_repeats] = telemetry.max_repeats
    end
  end

  def track_sql_query_telemetry(&block)
    telemetry = Sway::SqlQueryTelemetry.measure(
      on_complete: ->(res) { @sql_query_telemetry = res },
      &block
    )

    if !response.committed? && current_user&.is_sway_admin?
      metric = "sql_queries;desc=\"#{telemetry.queries} queries (max #{telemetry.max_repeats} repeats)\""
      existing = response.headers["Server-Timing"].presence
      response.headers["Server-Timing"] = existing ? "#{existing}, #{metric}" : metric
    end

    if !Rails.env.test? && telemetry.max_repeats >= Sway::SqlQueryTelemetry::N_PLUS_ONE_WARN_THRESHOLD
      SwayLogging.warn(
        "sql.n_plus_one_detected",
        controller: self.class.name,
        action: action_name,
        path: request.path,
        sql_queries_count: telemetry.queries,
        max_repeats: telemetry.max_repeats,
        top_fingerprint: telemetry.top_fingerprint
      )
    end
  end

  def enrich_with_first_legislator!(to_render)
    return unless params[:with]&.include?("legislator")

    first_legislator = current_user&.legislators(current_sway_locale)&.first
    to_render[:legislator] =
      first_legislator && LegislatorResource.new(first_legislator).serializable_hash
  end

  TRACKED_ARTICLE_BILL_CLICKS_SESSION_KEY = :tracked_article_bill_clicks
  MAX_TRACKED_ARTICLE_BILL_CLICKS = 100

  # @lat: [[partner-article-engagement#End-to-end attribution lifecycle]]
  def capture_attribution_param
    partner = params[:partner].presence
    ref = params[:ref].presence || params[:attribution].presence

    attribution_key = if partner.present?
      ref.present? ? "partner:#{partner}:#{ref}" : "partner:#{partner}"
    elsif ref.present?
      ref
    end

    return if attribution_key.blank?

    cookies.permanent[:sway_attribution_key] = attribution_key
    bill_id = params[:bill_id].presence || (params[:id].presence if controller_name == "bills")
    record_article_bill_click(attribution_key, bill_id: bill_id)
  end

  def record_article_bill_click(attribution_key, bill_id: nil)
    bill_id = bill_id.presence || params[:bill_id].presence || (params[:id].presence if controller_name == "bills")
    article_bill = ArticleEngagementTrackerService.resolve_article_bill(
      attribution_key: attribution_key,
      bill_id: bill_id
    )
    return unless article_bill

    tracked_ids = Array(session[TRACKED_ARTICLE_BILL_CLICKS_SESSION_KEY]).map(&:to_i)
    return if tracked_ids.include?(article_bill.id)

    ArticleEngagementTrackerService.track_click(article_bill: article_bill)
    session[TRACKED_ARTICLE_BILL_CLICKS_SESSION_KEY] = (tracked_ids << article_bill.id).last(MAX_TRACKED_ARTICLE_BILL_CLICKS)
  end

  def current_visitor_token
    @current_visitor_token ||= begin
      token = request.headers["X-Visitor-Token"].presence ||
        cookies[:sway_visitor_token].presence ||
        SecureRandom.uuid
      cookies.permanent[:sway_visitor_token] = token
      token
    end
  end

  def current_attribution_key
    cookies[:sway_attribution_key].presence
  end

  # @lat: [[bad-request-responses#Bad request responses#JavaScript format probes answer 406]]
  def reject_js_request_format
    head :not_acceptable if request.format.js?
  end
end
