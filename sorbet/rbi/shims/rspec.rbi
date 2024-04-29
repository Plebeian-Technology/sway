# typed: strict
# frozen_string_literal: true

# https://github.com/samuelgiles/rspec-sorbet/issues/12

module RSpec
  sig do
    params(
      args: T.untyped,
      block: T.proc.bind(T.untyped).void
    ).void
  end
  def self.describe(*args, &block)
  end

  sig do
    params(
      name: String,
      args: T.untyped,
      block: T.proc.bind(T.untyped).void
    ).void
  end
  def self.shared_examples(name, *args, &block)
  end
end
