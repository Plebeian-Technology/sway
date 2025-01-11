# frozen_string_literal: true
# typed: strict

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def to_sway_json
    to_builder.attributes!
  rescue NoMethodError => e
    Rails.logger.error(e.full_message)
  end
end
