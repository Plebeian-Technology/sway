# frozen_string_literal: true

module SwayProps
  extend ActiveSupport::Concern

  included do
    def expand_props(props)
      if props.nil?
        {}
      elsif props.is_a?(Hash)
        props
      else
        props.call
      end
    end
  end
end
