# frozen_string_literal: true

# @lat: [[identity-and-access#Registration is asynchronous by necessity]]
class RegistrationErrorResource < ApplicationResource
  attributes :code, :message
end
