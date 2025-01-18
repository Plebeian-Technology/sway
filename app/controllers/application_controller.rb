# frozen_string_literal: true
# typed: true

class ApplicationController < ActionController::Base
  extend T::Sig
  include RelyingParty
  include SwayProps
  include Pages

  protect_from_forgery with: :exception

  # newrelic_ignore_enduser

  before_action :redirect_if_no_current_user
  before_action :set_sway_locale_id_in_session

  T::Configuration.inline_type_error_handler = lambda do |error, _opts|
    Rails.logger.error error
  end

  helper_method :current_user, :current_sway_locale, :verify_is_admin

  @@_ssr_methods = {}

  ROUTES = T.let({
    HOME: "home",
    LEGISLATORS: "legislators",
    REGISTRATION: "sway_registration",
    BILL_OF_THE_WEEK: "bill_of_the_week",
    BILL: "bill",
    BILLS: "bills",
    BILL_CREATOR: "admin/bills/creator",
    INFLUENCE: "influence",
    INVITE: "invites/:user_id/:invite_uuid",
    NOTIFICATIONS: "notifications"
  }, T::Hash[Symbol, T.nilable(String)])

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
        route_component(ROUTES[:HOME])
        # redirect_to root_path
      end
    elsif !u.is_registration_complete && page != Pages::REGISTRATION
      # T.unsafe(self).route_registration
      redirect_to sway_registration_index_path
    else
      render inertia: page,
        props: {
          user: u.to_sway_json,
          swayLocale: current_sway_locale.to_builder.attributes!,
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
    T.unsafe(self).route_home if route.nil?

    phone = session[:verified_phone]

    u = current_user
    if u.nil?
      render json: {route: ROUTES[:HOME]}
    elsif !u.is_registration_complete
      render json: {route: ROUTES[:REGISTRATION], phone:}
    else
      Rails.logger.info "ServerRendering.route - Route to page - #{route}"

      render json: {route:, phone:}
    end
  end

  # https://www.leighhalliday.com/ruby-metaprogramming-method-missing
  sig do
    params(method_name: Symbol, args: T.untyped).void
  end
  def method_missing(method_name, *args)
    mn = method_name.to_s
    if mn.start_with?("route_")
      @@_ssr_methods[method_name] = lambda do
        Rails.logger.info "SSR ROUTING TO - #{mn}"
        route_component(ROUTES[T.cast(mn.split("_")[1..]&.map(&:upcase)&.join("_")&.to_sym, Symbol)])
      end
      @@_ssr_methods[method_name].call
    elsif mn.start_with?("redirect_")
      @@_ssr_methods[method_name] = lambda do
        Rails.logger.info "SSR REDIRECTING TO - #{mn}"
        redirect_component("#{mn.split("_")[1..]&.join("_")}_path")
      end
      @@_ssr_methods[method_name].call
    else
      raise NoMethodError.new("#{method_name} is not defined.")
    end
  end

  # https://www.leighhalliday.com/ruby-metaprogramming-method-missing
  def respond_to_missing?(method_name, include_private = false)
    @@_ssr_methods.include?(method_name.to_sym) || super
  end

  inertia_share flash: -> { flash.to_hash }

  # methods called in inertia_share must be called off of "self"
  # https://github.com/inertiajs/inertia-rails/issues/4#issuecomment-538493236
  inertia_share do
    {
      user: current_user, # rubocop:disable Style/RedundantSelf
      swayLocale: T.unsafe(self).current_sway_locale, # rubocop:disable Style/RedundantSelf
      swayLocales: T.unsafe(self).current_user&.sway_locales&.map&.call(&:to_sway_json) || [], # rubocop:disable Style/RedundantSelf
      params: {
        sway_locale_id: T.unsafe(self).params[:sway_locale_id] # rubocop:disable Style/RedundantSelf
      }
    }
  end

  private

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
      (User.find_by(id: session[:user_id]) if session[:user_id])
  end

  sig { returns(SwayLocale) }
  def current_sway_locale
    @current_sway_locale ||= lambda do
      l = SwayLocale.find_by(id: session[:sway_locale_id]) || current_user&.default_sway_locale
      raise "No Sway Locale found." if l.nil?
      l
    end.call
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
