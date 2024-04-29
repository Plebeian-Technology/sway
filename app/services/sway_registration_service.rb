# typed: true

# frozen_string_literal: true

class SwayRegistrationService
  extend T::Sig

  sig { params(user: User, name: String, address: Address).void }
  def initialize(user, name, address)
    @current_user = user
    @name = name
    @address = address
  end

  sig { void }
  def find_user_legsilators
  end
end
