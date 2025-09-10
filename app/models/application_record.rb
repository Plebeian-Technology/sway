# frozen_string_literal: true
# typed: strict

class ApplicationRecord < ActiveRecord::Base
    extend T::Sig

    primary_abstract_class

    sig { returns(T::Hash[String, String]) }
    def to_sway_json
        to_builder.attributes!.except("isA?", "is_a?")
    end

    sig { returns(Jbuilder) }
    def to_builder
        Jbuilder.new { |s| s.id id }
    end

    sig { returns(T::Hash[String, String]) }
    def attributes!
        T.cast(attributes, T::Hash[String, String]).except("isA?")
    end
end
