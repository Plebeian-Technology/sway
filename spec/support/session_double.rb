# https://stackoverflow.com/a/76342410/6410635

RSpec.shared_context "SessionDouble" do
  let(:session_hash) { {} }
  let(:cookies_hash) { {} }

  before do
    session_double =
      instance_double(
        ActionDispatch::Request::Session,
        enabled?: true,
        loaded?: false
      )

    allow(session_double).to receive(:[]) do |key|
      session_hash[key]
    end

    allow(session_double).to receive(:[]=) do |key, value|
      session_hash[key] = value
    end

    allow(session_double).to receive(:delete) do |key|
      session_hash.delete(key)
    end

    allow(session_double).to receive(:clear) do |_key|
      session_hash.clear
    end

    # reset_session — called by ApplicationController#sign_out, for example —
    # calls session.destroy, so this stand-in has to answer it. Otherwise any
    # action that signs a user out, such as deleting an account or a plain
    # sign-out, raises inside this context.
    allow(session_double).to receive(:destroy) do
      session_hash.clear
    end

    allow(session_double).to receive(:fetch) do |key|
      session_hash.fetch(key)
    end

    allow(session_double).to receive(:key?) do |key|
      session_hash.key?(key)
    end

    allow(session_double).to receive(:to_hash).and_return(session_hash)
    allow(session_double).to receive(:to_h).and_return(session_hash)

    allow(session_double).to receive(:dig) do |*keys|
      keys.reduce(session_hash) do |hash, key|
        next nil unless hash.is_a?(Hash)

        if hash.key?(key)
          hash[key]
        elsif key.is_a?(String) && hash.key?(key.to_sym)
          hash[key.to_sym]
        elsif key.is_a?(Symbol) && hash.key?(key.to_s)
          hash[key.to_s]
        end
      end
    end

    allow_any_instance_of(ActionDispatch::Request).to receive(
      :session
    ).and_return(session_double)

    # COOKIES

    cookies_double = instance_double(ActionDispatch::Cookies::CookieJar)

    allow(cookies_double).to receive(:[]) do |key|
      cookies_hash[key]
    end

    allow(cookies_double).to receive(:[]=) do |key, value|
      cookies_hash[key] = value
    end

    allow_any_instance_of(ActionDispatch::Cookies::CookieJar).to receive(
      :permanent
    ).and_return(cookies_hash)
    allow_any_instance_of(ActionDispatch::Cookies::CookieJar).to receive(
      :encrypted
    ).and_return(cookies_hash)
    allow_any_instance_of(ActionDispatch::Cookies::CookieJar).to receive(
      :signed
    ).and_return(cookies_hash)
  end

  # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#Request specs switch the complete authentication identity]]
  def sign_in(user)
    session_hash[:user_id] = user.id
    session_hash[:auth_identity] = user.created_at.to_i
  end
end
