# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def to_sway_json
    to_builder.attributes!.except("isA?", "is_a?")
  end

  def to_builder
    Jbuilder.new { |s| s.id id }
  end

  def attributes!
    attributes.except("isA?")
  end
end
