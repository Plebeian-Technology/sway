# frozen_string_literal: true
# typed: false

class ApplicationController < ActionController::Base
  extend T::Sig
  include DefaultMetaTaggable
  include RelyingParty
  include ApiKeyAuthenticatable
  include SwayProps
  include Pages
  include SwayRoutes

  rate_limit(to: 200, within: 1.minute, by: -> { request.domain })

  # https://inertia-rails.dev/guide/csrf-protection#handling-mismatches
  rescue_from ActionController::InvalidAuthenticityToken,
              with: :inertia_page_expired_error

  # https://api.rubyonrails.org/classes/ActionController/RequestForgeryProtection/ClassMethods.html
  protect_from_forgery with: :exception, prepend: true

  # newrelic_ignore_enduser

  before_action :is_api_request_and_is_route_api_accessible?
  before_action :authenticate_sway_user!
  before_action :set_sway_locale_id_in_session

  after_action :add_rsl_license_header

  inertia_config(
    # ..........*......DEPRECATION WARNING: To comply with the Inertia protocol, an empty errors hash `{errors: {}}` will be included to all responses by default starting with InertiaRails 4.0. To opt-in now, set `config.always_include_errors_hash = true`. To disable this warning, set it to `false`. (called from ApplicationController#render_component at /Users/dave/plebtech/sway/app/controllers/application_controller.rb:42)
    always_include_errors_hash: true,
  )

  T::Configuration.inline_type_error_handler =
    lambda { |error, _opts| Rails.logger.error error }

  helper_method :current_user,
                :current_sway_locale,
                :verify_is_sway_admin,
                :invited_by_id

  @@_ssr_methods = {}

  sig { params(page: T.nilable(String), props: T.untyped).returns(T.untyped) }
  def render_component(page, props = {})
    return render_component(Pages::HOME) if page.nil?

    render(inertia: page, props: expand_props(props))
  end

  sig do
    params(
      route: T.nilable(String),
      new_params: T::Hash[T.any(String, Symbol), T.anything],
    ).returns(T.untyped)
  end
  def route_component(route, new_params = {})
    return route_component(SwayRoutes::HOME) if route.nil?

    phone = session[:verified_phone]

    Rails.logger.info "ServerRendering.route - Route to page - #{route}"

    render json: { route:, phone:, params: new_params }
    # end
  end

  inertia_share flash: -> { flash.to_hash }

  inertia_share do
    {
      user:
        current_user&.to_sway_json&.merge(
          { address: current_user&.address&.attributes },
        ),
      sway_locale: current_sway_locale&.to_sway_json,
      sway_locales:
        current_user&.sway_locales&.map(&:to_sway_json) ||
          SwayLocale.all&.map(&:to_sway_json),
      params: {
        sway_locale_id: params[:sway_locale_id],
        errors: params[:errros],
      },
    }
  end

  sig { params(user: T.nilable(User)).returns(T.untyped) }
  def sign_in(user)
    return if user.blank?

    _invited_by_id = invited_by_id

    # Reset session on sign_in to prevent session fixation attacks
    # https://guides.rubyonrails.org/security.html#session-fixation-countermeasures
    reset_session

    # Need to persist this value through registration
    cookies.permanent[UserInviter::INVITED_BY_SESSION_KEY] = _invited_by_id

    begin
      cookies.encrypted[:refresh_token] = RefreshToken.for(
        user,
        request,
      ).as_cookie
      session[:user_id] = user.id

      user.sign_in_count = user.sign_in_count + 1
      user.last_sign_in_at = user.current_sign_in_at
      user.current_sign_in_at = Time.zone.now
      user.last_sign_in_ip = user.current_sign_in_ip
      user.current_sign_in_ip = request.remote_ip
      user.save

      cookies.permanent[
        :sway_locale_id
      ] = user.default_sway_locale&.id if user.is_registration_complete
    rescue StandardError => e
      reset_session
      cookies.clear
      raise e
    end
  end

  sig { void }
  def sign_out
    current_user&.refresh_token&.destroy
    reset_session
    cookies.clear
  end

  sig { returns(T.nilable(User)) }
  def current_user
    @current_user ||= authenticate_with_cookies || authenticate_with_api_key # ApiKeyAuthenticatable
  end

  sig { returns(T.nilable(SwayLocale)) }
  def current_sway_locale
    @current_sway_locale ||= find_current_sway_locale
  end

  def invited_by_id
    Rails.logger.info "Getting invited_by_id from cookies: #{cookies.permanent[UserInviter::INVITED_BY_SESSION_KEY]}"
    cookies.permanent[UserInviter::INVITED_BY_SESSION_KEY]
  end

  def authenticate_with_cookies
    u = User.find_by(id: session[:user_id])

    if u.nil? && cookies.encrypted[:refresh_token].present?
      current_refresh_token =
        RefreshToken.find_by(token: cookies.encrypted[:refresh_token])

      if current_refresh_token&.is_valid?(request)
        Rails.logger.info(
          "authenticate_with_cookies - refreshing User with Refresh Token",
        )
        u = current_refresh_token.user
        if u.present?
          session[:user_id] = u.id
          cookies.encrypted[:refresh_token] = RefreshToken.for(
            u,
            request,
          ).as_cookie
        end
      end
    end
    u
  end

  sig { void }
  def is_api_request_and_is_route_api_accessible?
    if request.path.starts_with?("/api/admin/")
      unless authenticate_with_api_key! && current_user&.is_sway_admin?
        render json: {
                 message:
                   "Missing API Key. Include it an Authorization header.",
               },
               status: :accepted
      end
    elsif request.path.starts_with?("/api/")
      unless authenticate_with_api_key!
        render json: {
                 message:
                   "Missing API Key. Include it an Authorization header.",
               },
               status: :accepted
      end
    end
  end

  sig { void }
  def authenticate_sway_user!
    u = current_user
    if u.nil?
      Rails.logger.info "No current user, redirect to root path"
      redirect_to root_url
    elsif !u.is_registration_complete
      if u.has_user_legislators?
        u.is_registration_complete = true
        u.save!
      else
        Rails.logger.info "Current user registration is not complete, redirect to sway registration"
        redirect_to sway_registration_index_path
      end
    end
  end

  sig { void }
  def verify_is_sway_admin
    redirect_to root_path unless current_user&.is_sway_admin?
  end

  private

  def set_sway_locale_id_in_session
    return if params[:sway_locale_id].blank?

    cookies.permanent[:sway_locale_id] = params[:sway_locale_id].to_i
  end

  def find_current_sway_locale
    SwayLocale.find_by(id: cookies.permanent[:sway_locale_id]) ||
      SwayLocale.find_by_name(params[:sway_locale_name]) || # query string for sharing
      current_user&.default_sway_locale || SwayLocale.default_locale # congress
  end

  def inertia_page_expired_error
    redirect_back_or_to(
      "/",
      allow_other_host: false,
      notice: "The page expired, please try again.",
    )
  end

  # https://rslstandard.org/guide/http
  # https://arstechnica.com/tech-policy/2025/09/pay-per-output-ai-firms-blindsided-by-beefed-up-robots-txt-instructions/
  def add_rsl_license_header
    response.set_header(
      "Link",
      'https://www.sway.vote/license.xml; rel="license"; type="application/rsl+xml',
    )
  end
end
