# frozen_string_literal: true
# typed: true

module SwayProps
    extend T::Sig
    extend ActiveSupport::Concern

    included do
        sig do
            params(
                props: T.nilable(T.any(T::Hash[T.untyped, T.untyped], T.proc.returns(T::Hash[T.untyped, T.untyped]))),
            ).returns(T::Hash[T.untyped, T.untyped])
        end
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
