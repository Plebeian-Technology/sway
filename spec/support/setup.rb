# spec/support/session_double.rb
# https://stackoverflow.com/a/76342410/6410635

shared_context "Setup" do
  def setup
    address = create(:address)
    sway_locale = create(:sway_locale, city: address.city, state: address.region_code, country: address.country)
    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:)

    user = create(:user, is_registration_complete: true) do |u|
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, u.phone)
      User.send(:remove_const, :API_USER_PHONES)
      User.const_set(:API_USER_PHONES, u.phone)
      session_hash[:user_id] = u.id
      session_hash[:sway_locale_id] = sway_locale.id

      cookies_hash[:user_id] = u.id
      cookies_hash[:sway_locale_id] = sway_locale.id
    end

    create(:user_legislator, user:, legislator:)

    [sway_locale, user]
  end
end
