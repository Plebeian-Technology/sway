# frozen_string_literal: true

# @lat: [[env-helpers-with-env-consolidation#Why with_app_config joins with_env rather than replacing it]]
module EnvHelpers
  # @param pairs [Hash[String, String?]] nil means "make sure this is unset"
  # @yield with the environment changed
  # @return whatever the block returns
  def with_env(pairs)
    # Built by hand rather than with to_h: a two-element array literal in a
    # block reads as a plain array, not as a key-and-value pair, so the type
    # of `saved` would be lost. Two of the five copies this replaces carried
    # the same annotation, which says the wall was hit before.
    saved = {} #: Hash[String, String?]
    pairs.each_key { |key| saved[key] = ENV.fetch(key, nil) }
    begin
      pairs.each { |key, value| write_env(key, value) }
      yield
    ensure
      saved.each { |key, value| write_env(key, value) }
    end
  end

  # @lat: [[env-helpers-with-env-consolidation#Why with_app_config joins with_env rather than replacing it]]
  #
  # @param group [Symbol] a key in Sway::Settings::GROUPS, e.g. :upstream
  # @param overrides [Hash[Symbol, untyped]] attribute overrides for the group
  # @yield with the group instance replaced
  # @return whatever the block returns
  def with_app_config(group, **overrides)
    klass = Sway::Settings::GROUPS.fetch(group)
    previous = Sway::Settings.public_send(group)
    begin
      Sway::Settings.install(group, klass.new(overrides))
      yield
    ensure
      Sway::Settings.install(group, previous)
    end
  end

  # @lat: [[env-helpers-with-env-consolidation#Why generate_bill_summary_job_spec.rb uses stub_app_config plus a file-wide after, not with_app_config]]
  #
  # @param group [Symbol] a key in Sway::Settings::GROUPS, e.g. :llm
  # @param overrides [Hash[Symbol, untyped]] attribute overrides for the group
  # @return [Sway::Settings::Base] the new instance, now installed
  def stub_app_config(group, **overrides)
    klass = Sway::Settings::GROUPS.fetch(group)
    Sway::Settings.install(group, klass.new(overrides))
  end

  private

  # nil deletes. Spelled out rather than leaning on ENV#[]= doing it, so a
  # reader does not have to know that Ruby detail to follow the restore above.
  def write_env(key, value)
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
  end
end

RSpec.configure do |c|
  c.include EnvHelpers
end
