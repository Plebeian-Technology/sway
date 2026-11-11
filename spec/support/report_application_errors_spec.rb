# frozen_string_literal: true

require "rails_helper"

# @lat: [[error-reporting-in-tests#What a test run reports, and what it leaves alone]]
RSpec.describe ReportApplicationErrors do
  # Hands back what aggregate_failures raised, so examples see a real bundle.
  def capture_aggregate_failure(&block)
    aggregate_failures("a deliberate bundle", &block)
    nil
  rescue RSpec::Expectations::MultipleExpectationsNotMetError => e
    e
  end

  describe ".application_errors" do
    it "sends nothing when the example passed" do
      expect(described_class.application_errors(nil)).to eq([])
    end

    it "sends an error the app raised and nobody caught" do
      error = StandardError.new("the app broke")

      expect(described_class.application_errors(error)).to eq([error])
    end

    it "sends nothing for an expectation that did not hold" do
      failure = RSpec::Expectations::ExpectationNotMetError.new("expected true, got false")

      expect(described_class.application_errors(failure)).to eq([])
    end

    it "sends nothing for a message the test demanded and never got" do
      failure = RSpec::Mocks::MockExpectationError.new("expected :foo once, got 0 times")

      expect(described_class.application_errors(failure)).to eq([])
    end

    it "sends nothing for a pending test that passed" do
      fixed = RSpec::Core::Pending::PendingExampleFixedError.new("Expected example to fail")

      expect(described_class.application_errors(fixed)).to eq([])
    end

    # An example can fail an expectation AND break the app.
    it "opens a bundle of failures and keeps only the app's own" do
      failure = RSpec::Expectations::ExpectationNotMetError.new("expected true, got false")
      error = StandardError.new("and the teardown blew up")
      bundle = RSpec::Core::MultipleExceptionError.new(failure, error)

      expect(described_class.application_errors(bundle)).to eq([error])
    end

    it "sends nothing when every failure in the bundle is about the test" do
      bundle = RSpec::Core::MultipleExceptionError.new(
        RSpec::Expectations::ExpectationNotMetError.new("first"),
        RSpec::Expectations::ExpectationNotMetError.new("second")
      )

      expect(described_class.application_errors(bundle)).to eq([])
    end

    # @lat: [[application-errors-sentry-relay-design#Why the recursion is duck-typed on respond_to?(:all_exceptions)]]
    it "opens an aggregate_failures bundle too" do
      bundle = capture_aggregate_failure do
        expect(true).to be(false)
        raise StandardError, "the app broke inside aggregate_failures"
      end

      expect(described_class.application_errors(bundle).map(&:message))
        .to eq(["the app broke inside aggregate_failures"])
    end

    # Otherwise one failing test recurses until the stack runs out.
    it "does not follow a bundle that lists itself" do
      bundle = RSpec::Core::MultipleExceptionError.new(StandardError.new("real"))
      bundle.all_exceptions << bundle

      expect(described_class.application_errors(bundle).map(&:message)).to eq(["real"])
    end
  end

  describe ".tags_for" do
    it "names the test, so a report can be traced back to it" do
      tags = described_class.tags_for(RSpec.current_example)

      expect(tags["rspec.example"]).to include("report_application_errors_spec.rb")
      expect(tags["rspec.description"]).to include("names the test")
    end
  end
end
