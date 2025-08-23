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

  # https://inertia-rails.dev/guide/csrf-protection#handling-mismatches
  rescue_from ActionController::InvalidAuthenticityToken, with: :inertia_page_expired_error

  # https://api.rubyonrails.org/classes/ActionController/RequestForgeryProtection/ClassMethods.html
  protect_from_forgery with: :exception, prepend: true

  # newrelic_ignore_enduser

  before_action :is_api_request_and_is_route_api_accessible?
  before_action :authenticate_user!
  before_action :set_sway_locale_id_in_session

  T::Configuration.inline_type_error_handler = lambda do |error, _opts|
    Rails.logger.error error
  end

  helper_method :current_user, :current_sway_locale, :verify_is_admin

  @@_ssr_methods = {}

  sig do
    params(
      page: T.nilable(String),
      props: T.untyped
    ).returns(T.untyped)
  end
  def render_component(page, props = {})
    return render_component(Pages::HOME) if page.nil?

    render(inertia: page, props: expand_props(props))
  end

  sig { params(route: T.nilable(String), new_params: T::Hash[T.any(String, Symbol), T.anything]).returns(T.untyped) }
  def route_component(route, new_params = {})
    return route_component(SwayRoutes::HOME) if route.nil?

    phone = session[:verified_phone]

    Rails.logger.info "ServerRendering.route - Route to page - #{route}"

    render json: {route:, phone:, params: new_params}
    # end
  end

  inertia_share flash: -> { flash.to_hash }

  inertia_share do
    {
      user: current_user&.to_sway_json&.merge({
        address: current_user&.address&.attributes
      }),
      sway_locale: current_sway_locale&.to_sway_json,
      sway_locales: current_user&.sway_locales&.map(&:to_sway_json) || SwayLocale.all&.map(&:to_sway_json),
      params: {
        sway_locale_id: params[:sway_locale_id],
        errors: params[:errros]
      }
    }
  end

  sig { params(user: T.nilable(User)).returns(T.untyped) }
  def sign_in(user)
    return if user.blank?

    invited_by_id = cookies.permanent[UserInviter::INVITED_BY_SESSION_KEY]

    # Reset session on sign_in to prevent session fixation attacks
    # https://guides.rubyonrails.org/security.html#session-fixation-countermeasures
    reset_session

    # Need to persist this value through registration
    cookies.permanent[UserInviter::INVITED_BY_SESSION_KEY] = invited_by_id

    begin
      cookies.encrypted[:refresh_token] = RefreshToken.for(user, request).as_cookie
      session[:user_id] = user.id

      user.sign_in_count = user.sign_in_count + 1
      user.last_sign_in_at = user.current_sign_in_at
      user.current_sign_in_at = Time.zone.now
      user.last_sign_in_ip = user.current_sign_in_ip
      user.current_sign_in_ip = request.remote_ip
      user.save

      if user.is_registration_complete
        cookies.permanent[:sway_locale_id] = user.default_sway_locale&.id
      end
    rescue => e
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
    @_current_sway_locale ||= find_current_sway_locale
  end

  def authenticate_with_cookies
    u = User.find_by(id: session[:user_id])

    if u.nil? && cookies.encrypted[:refresh_token].present?
      current_refresh_token = RefreshToken.find_by(token: cookies.encrypted[:refresh_token])

      if current_refresh_token&.is_valid?(request)
        Rails.logger.info("authenticate_with_cookies - refreshing User with Refresh Token")
        u = current_refresh_token.user
        if u.present?
          session[:user_id] = u.id
          cookies.encrypted[:refresh_token] = RefreshToken.for(u, request).as_cookie
        end
      end
    end
    u
  end

  sig { void }
  def is_api_request_and_is_route_api_accessible?
    if request.path.starts_with?("/api/admin/")
      unless authenticate_with_api_key! && current_user&.is_admin?
        render json: {
          message: "Missing API Key. Include it an Authorization header."
        }, status: :accepted
      end
    elsif request.path.starts_with?("/api/")
      unless authenticate_with_api_key!
        render json: {
          message: "Missing API Key. Include it an Authorization header."
        }, status: :accepted
      end
    end
  end

  sig { void }
  def authenticate_user!
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
  def verify_is_admin
    redirect_to root_path unless current_user&.is_admin?
  end

  private

  def set_sway_locale_id_in_session
    return if params[:sway_locale_id].blank?

    cookies.permanent[:sway_locale_id] = params[:sway_locale_id].to_i
  end

  def find_current_sway_locale
    SwayLocale.find_by(id: cookies.permanent[:sway_locale_id]) ||
      SwayLocale.find_by_name(params[:sway_locale_name]) || # # rubocop:disable Rails/DynamicFindBy, set in query string for sharing
      current_user&.default_sway_locale ||
      SwayLocale.default_locale # congress
  end

  def inertia_page_expired_error
    redirect_back_or_to("/", allow_other_host: false, notice: "The page expired, please try again.")
  end
end
