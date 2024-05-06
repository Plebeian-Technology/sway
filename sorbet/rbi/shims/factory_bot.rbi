# typed: strict
# frozen_string_literal: true

# https://github.com/samuelgiles/rspec-sorbet/issues/12

module FactoryBot
  sig do
    params(
      block: T.proc.bind(T.untyped).void
    ).void
  end
  def self.define(&block)
  end
end
