# frozen_string_literal: true

# @lat: [[testimony-letters#Selecting browsable constituent letters]]
class PublicTestimonyLetterResource < ApplicationResource
  attributes :position, :label, :stance, :body_text
end
