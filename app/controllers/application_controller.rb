# frozen_string_literal: true
# typed: true

class ApplicationController < ActionController::Base
  extend T::Sig
  include RelyingParty
  include SwayProps
  include Pages
  include SwayRoutes

  protect_from_forgery with: :exception

  # newrelic_ignore_enduser

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
    if u.nil?
      if page == Pages::HOME
        render inertia: page, props:
      else
        route_component(SwayRoutes::HOME)
        # redirect_to root_path
      end
    elsif !u.is_registration_complete && page != Pages::REGISTRATION
      redirect_to sway_registration_index_path
    else
      render inertia: page,
        props: {
          user: u.to_sway_json,
          swayLocale: current_sway_locale&.to_sway_json,
          **expand_props(props)
        }
    end
  end

  sig do
    params(
      page: T.nilable(String),
      props: T.untyped
    ).returns(T.untyped)
  end
  def redirect_component(page, props = {})
    redirect_to root_path if page.nil?

    u = current_user
    if u.nil?
      redirect_to root_path, inertia: props
    elsif !u.is_registration_complete && page != Pages::REGISTRATION
      redirect_to sway_registration_index_path, inertia: props
    else
      redirect_to send(T.cast(page, String)), inertia: props
    end
  end

  sig { params(route: T.nilable(String)).returns(T.untyped) }
  def route_component(route)
    return route_component(SwayRoutes::HOME) if route.nil?

    phone = session[:verified_phone]

    u = current_user
    if u.nil?
      render json: {route: SwayRoutes::HOME}
    elsif !u.is_registration_complete
      render json: {route: SwayRoutes::REGISTRATION, phone:}
    else
      Rails.logger.info "ServerRendering.route - Route to page - #{route}"

      render json: {route:, phone:}
    end
  end

  inertia_share flash: -> { flash.to_hash }

  # methods called in inertia_share must be called off of "self"
  # https://github.com/inertiajs/inertia-rails/issues/4#issuecomment-538493236
  inertia_share do
    {
      user: current_user,
      swayLocale: current_sway_locale,
      swayLocales: current_user&.sway_locales&.map(&:to_sway_json) || [],
      params: {
        sway_locale_id: params[:sway_locale_id]
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
      User.find_by(id: session[:user_id])
  end

  sig { returns(T.nilable(SwayLocale)) }
  def current_sway_locale
    @current_sway_locale ||= SwayLocale.find_by(id: session[:sway_locale_id]) || current_user&.default_sway_locale
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
end
