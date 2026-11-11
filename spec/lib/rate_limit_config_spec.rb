# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateLimitConfig do
  # The comparison is text against text; anything but the literal word makes
  # it false, silently switching a rate limit off in production. T-68-13.
  describe ".enabled?" do
    context "in test environment (default)" do
      it "returns false regardless of the setting" do
        expect(described_class.enabled?(:sign_in)).to be false
      end

      it "returns false even when sign_in_enabled is true (the production guard, not a setting, T-68-16)" do
        with_app_config(:rate_limits, sign_in_enabled: true) do
          expect(described_class.enabled?(:sign_in)).to be false
        end
      end
    end

    context "in production environment" do
      before { allow(Rails.env).to receive(:production?).and_return(true) }

      RateLimitConfig::FLAG_FOR.each do |scope, attribute|
        it "enables #{scope} when #{attribute} is unset (default true)" do
          expect(described_class.enabled?(scope)).to be true
        end

        it "disables #{scope}, and only #{scope}, when #{attribute} is set to false" do
          with_app_config(:rate_limits, **{attribute => false}) do
            expect(described_class.enabled?(scope)).to be false

            (RateLimitConfig::FLAG_FOR.keys - [scope]).each do |other_scope|
              expect(described_class.enabled?(other_scope)).to be true
            end
          end
        end

        it "enables #{scope} when #{attribute} is explicitly set to true" do
          with_app_config(:rate_limits, **{attribute => true}) do
            expect(described_class.enabled?(scope)).to be true
          end
        end
      end
    end

    it "raises KeyError on unknown scope, not false" do
      expect { described_class.enabled?(:unknown_key) }.to raise_error(KeyError)
    end
  end

  # @lat: [[rate-limit-kill-switches#Why the blank-repair spec builds a fresh settings instance per variable]]
  describe "blank repair, one per variable" do
    RateLimitConfig::FLAG_FOR.each do |scope, attribute|
      env_name = [Sway::Settings::RateLimits.env_prefix, attribute.to_s.upcase].join("_")

      it "repairs #{env_name} back to true when it is an empty string (#{scope})" do
        with_env(env_name => "") do
          expect(Sway::Settings::RateLimits.new.public_send(attribute)).to be true
        end
      end

      it "repairs #{env_name} back to true when it is spaces only (#{scope})" do
        with_env(env_name => "   ") do
          expect(Sway::Settings::RateLimits.new.public_send(attribute)).to be true
        end
      end
    end
  end
end
