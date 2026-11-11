# frozen_string_literal: true

# @lat: [[identity-and-access#Registration is asynchronous by necessity]]
class RegistrationOutcomeResource < ApplicationResource
  attributes :reason, :message
end
