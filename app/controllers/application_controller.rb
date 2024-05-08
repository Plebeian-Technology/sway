# typed: true

class ApplicationController < ActionController::Base
  extend T::Sig
  include RelyingParty
  include SwayProps

  before_action :redirect_if_no_current_user

  T::Configuration.inline_type_error_handler = lambda do |error, _opts|
    Rails.logger.error error
  end

  helper_method :current_user, :current_sway_locale, :verify_is_admin

  @@SSRMethods = {}

  ROUTES = T.let({
                   HOME: 'home',
                   LEGISLATORS: 'legislators',
                   REGISTRATION: 'sway_registration',
                   BILL_OF_THE_WEEK: 'bill_of_the_week',
                   BILLS: 'bills',
                   BILL: 'bill',
                   INFLUENCE: 'influence',
                   INVITE: 'invite/:user_id',
                   BILL_CREATOR: 'admin/bills/creator'
                 }, T::Hash[Symbol, T.nilable(String)])

  PAGES = T.let({
                  HOME: 'Home',
                  LEGISLATORS: 'Legislators',
                  REGISTRATION: 'Registration',
                  BILL_OF_THE_WEEK: 'BillOfTheWeek',
                  BILLS: 'Bills',
                  BILL: 'Bill',
                  INFLUENCE: 'Influence',
                  INVITE: 'Invite',
                  BILL_CREATOR: 'BillOfTheWeekCreator'
                }, T::Hash[Symbol, T.nilable(String)])

  sig do
    params(
      page: T.nilable(String),
      props: T.untyped
    ).returns(T.untyped)
  end
  def render_component(page, props = {})
    T.unsafe(self).render_home if page.nil?

    u = current_user
    if u.nil?
      if page == PAGES[:HOME]
        render inertia: page, props:
      else
        # T.unsafe(self).route_home
        redirect_to root_path
      end
    elsif !u.is_registration_complete && page != PAGES[:REGISTRATION]
      # T.unsafe(self).route_registration
      redirect_to sway_registration_index_path
    else
      # redirect_to legislator_path
      render inertia: page,
             props: {
               user: u.to_builder.attributes!,
               sway_locale: current_sway_locale&.to_builder(current_user)&.attributes!,
               **expand_props(props)
             }
    end
  end

  sig { params(route: T.nilable(String)).returns(T.untyped) }
  def route_component(route)
    T.unsafe(self).route_home if route.nil?

    u = current_user
    if u.nil?
      render json: { route: ROUTES[:HOME] }
    elsif !u.is_registration_complete
      render json: { route: ROUTES[:REGISTRATION] }
    else
      Rails.logger.info "ServerRendering.route - Route to page - #{route}"
      render json: { route: }
    end
  end

  # https://www.leighhalliday.com/ruby-metaprogramming-method-missing
  sig do
    params(method_name: Symbol,
           args: T::Array[T.nilable(T.any(T::Hash[T.untyped, T.untyped],
                                          T.proc.returns(T::Hash[T.untyped, T.untyped])))]).void
  end
  def method_missing(method_name, *args)
    mn = method_name.to_s
    if mn.start_with?('render_')
      @@SSRMethods[method_name] = lambda do
        Rails.logger.info "SSR RENDERING - #{mn}"
        page = PAGES.dig(T.cast(mn.split('_')[1..]&.map(&:upcase)&.join('_')&.to_sym, Symbol))
        callable = T.cast(args.first, T.nilable(T.any(T::Hash[T.untyped, T.untyped], T.proc.returns(T::Hash[T.untyped, T.untyped]))))

        if callable.nil?
          render_component(page)
        else
          render_component(page, callable)
        end
      end
      @@SSRMethods[method_name].call
    elsif mn.start_with?('route_')
      @@SSRMethods[method_name] = lambda do
        Rails.logger.info "SSR ROUTING TO - #{mn}"
        route_component(ROUTES.dig(T.cast(mn.split('_')[1..]&.map(&:upcase)&.join('_')&.to_sym, Symbol)))
      end
      @@SSRMethods[method_name].call
    else
      raise NoMethodError
    end
  end

  # https://www.leighhalliday.com/ruby-metaprogramming-method-missing
  def respond_to?(method_name, include_private = false)
    @@SSRMethods.include?(method_name.to_sym) || super
  end

  sig { void }
  def test_recaptcha
    raise Errno::ECONNABORTED unless RecaptchaUtil.valid?(params[:token])
  end

  private

  sig { params(user: T.nilable(User)).returns(T.untyped) }
  def sign_in(user)
    return unless user.present?

    # Reset session on sign_in to prevent session fixation attacks
    # https://guides.rubyonrails.org/security.html#session-fixation-countermeasures
    reset_session

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

  sig { returns(T.nilable(SwayLocale)) }
  def current_sway_locale
    @current_sway_locale ||=
      SwayLocale.find_by(id: session[:sway_locale_id]) || current_user&.default_sway_locale
  end

  sig { void }
  def redirect_if_no_current_user
    u = current_user
    if u.nil?
      Rails.logger.info 'No current user, redirect to root path'
      redirect_to root_path
    elsif !u.is_registration_complete
      if u.has_user_legislators?
        u.is_registration_complete = true
        u.save!
      else
        Rails.logger.info 'Current user registration is not complete, redirect to sway registration'
        redirect_to sway_registration_index_path
      end
    end
  end

  sig { returns(T::Boolean) }
  def verify_is_admin
    unless current_user&.is_admin?
      redirect_to root_path
    end
  end
end
