# frozen_string_literal: true
# typed: false

class ApplicationController < ActionController::Base
  extend T::Sig
  include RelyingParty
  include ApiKeyAuthenticatable
  include SwayProps
  include Pages
  include SwayRoutes

  protect_from_forgery with: :exception

  # newrelic_ignore_enduser

  before_action :is_api_request_and_is_route_api_accessible?
  before_action :redirect_if_no_current_user
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

    u = current_user
    render inertia: page,
      props: {
        user: u&.to_sway_json,
        swayLocale: current_sway_locale&.to_sway_json,
        **expand_props(props)
      }
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
      user: current_user,
      swayLocale: current_sway_locale,
      swayLocales: current_user&.sway_locales&.map(&:to_sway_json) || SwayLocale.all&.map(&:to_sway_json),
      params: {
        sway_locale_id: params[:sway_locale_id],
        errors: params[:errros]
      }
    }
  end

  sig { params(user: T.nilable(User)).returns(T.untyped) }
  def sign_in(user)
    return if user.blank?

    invited_by_id = session[UserInviter::INVITED_BY_SESSION_KEY]

    # Reset session on sign_in to prevent session fixation attacks
    # https://guides.rubyonrails.org/security.html#session-fixation-countermeasures
    reset_session

    # Need to persist this value through registration
    session[UserInviter::INVITED_BY_SESSION_KEY] = invited_by_id

    session[:user_id] = user.id
    user.sign_in_count = user.sign_in_count + 1
    user.last_sign_in_at = user.current_sign_in_at
    user.current_sign_in_at = Time.zone.now
    user.last_sign_in_ip = user.current_sign_in_ip
    user.current_sign_in_ip = request.remote_ip
    user.save

    session[:sway_locale_id] ||= user.default_sway_locale&.id
  end

  sig { void }
  def sign_out
    reset_session
  end

  sig { returns(T.nilable(User)) }
  def current_user
    @current_user ||=
      User.find_by(id: session[:user_id]) ||
      authenticate_with_api_key # ApiKeyAuthenticatable
  end

  sig { returns(T.nilable(SwayLocale)) }
  def current_sway_locale
    @current_sway_locale ||= find_current_sway_locale
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
  def redirect_if_no_current_user
    u = current_user
    if u.nil?
      Rails.logger.info "No current user, redirect to root path"
      redirect_to root_path
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

  def set_sway_locale_id_in_session
    return if params[:sway_locale_id].blank?

    session[:sway_locale_id] = params[:sway_locale_id].to_i
  end

  private

  def find_current_sway_locale
    SwayLocale.find_by(id: session[:sway_locale_id]) ||
      SwayLocale.find_by_name(params[:sway_locale_name]) || # # rubocop:disable Rails/DynamicFindBy, set in query string for sharing
      current_user&.default_sway_locale ||
      SwayLocale.default_locale # congress
  end
end
