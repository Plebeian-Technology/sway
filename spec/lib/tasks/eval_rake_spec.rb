# frozen_string_literal: true

require "rails_helper"
require "rake"

# @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why sway:eval tasks stay thin over Eval:: services]]
RSpec.describe "sway:eval rake tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:eval:dump")
  end

  before do
    Rake::Task["sway:eval:dump"].reenable
    Rake::Task["sway:eval:score"].reenable
    Rake::Task["sway:eval:reference_set"].reenable
  end

  describe "sway:eval:dump" do
    it "aborts naming the task to run first when eval/reference-set.json is absent" do
      allow(Eval::PromptDump).to receive(:assert_non_development_caps!)
      fake_path = instance_double(Pathname, exist?: false)
      allow(Rails.root).to receive(:join).and_call_original
      allow(Rails.root).to receive(:join).with("eval", "reference-set.json").and_return(fake_path)

      expect { Rake::Task["sway:eval:dump"].invoke }.to raise_error(SystemExit)
      Rake::Task["sway:eval:dump"].reenable
      expect {
        begin
          Rake::Task["sway:eval:dump"].invoke
        rescue SystemExit
          nil
        end
      }.to output(/sway:eval:reference_set/).to_stderr
    end

    it "aborts naming the count when a pick's external_id matches zero or more than one Bill" do
      allow(Eval::PromptDump).to receive(:assert_non_development_caps!)
      reference_set = [{"external_id" => "25-9999", "answer_types" => ["summary"]}].to_json
      fake_set_path = instance_double(Pathname, exist?: true, read: reference_set)
      allow(Rails.root).to receive(:join).and_call_original
      allow(Rails.root).to receive(:join).with("eval", "reference-set.json").and_return(fake_set_path)
      allow(Bill).to receive(:where).with(external_id: "25-9999").and_return(Bill.none)

      expect { Rake::Task["sway:eval:dump"].invoke }.to raise_error(SystemExit)
    end

    it "refuses to write a partial manifest, listing every failed bill/answer-type pair" do
      allow(Eval::PromptDump).to receive(:assert_non_development_caps!)
      reference_set = [
        {"external_id" => "25-0001", "answer_types" => ["summary"]},
        {"external_id" => "25-0002", "answer_types" => ["positions"]}
      ].to_json
      fake_set_path = instance_double(Pathname, exist?: true, read: reference_set)
      allow(Rails.root).to receive(:join).and_call_original
      allow(Rails.root).to receive(:join).with("eval", "reference-set.json").and_return(fake_set_path)

      bill_one = instance_double(Bill, external_id: "25-0001")
      bill_two = instance_double(Bill, external_id: "25-0002")
      allow(Bill).to receive(:where).with(external_id: "25-0001").and_return([bill_one])
      allow(Bill).to receive(:where).with(external_id: "25-0002").and_return([bill_two])
      allow(Eval::PromptDump).to receive(:call).with(bill: bill_one, answer_type: "summary")
        .and_raise(Eval::PromptDump::MissingDiffMarkdownError, "no diff")
      allow(Eval::PromptDump).to receive(:call).with(bill: bill_two, answer_type: "positions")
        .and_raise(Eval::PromptDump::MissingSourceError, "no source")

      expect { Rake::Task["sway:eval:dump"].invoke }.to raise_error(SystemExit)
    end

    it "aborts via the development-caps refusal when caps are not the non-development values" do
      allow(Eval::PromptDump).to receive(:assert_non_development_caps!)
        .and_raise(Eval::PromptDump::DevelopmentCapsError, "wrong caps")

      expect { Rake::Task["sway:eval:dump"].invoke }.to raise_error(SystemExit)
    end
  end

  describe "sway:eval:reference_set" do
    it "catches BandCollisionError by name and aborts rather than raising" do
      allow(Eval::ReferenceSetSelector).to receive(:call)
        .and_raise(Eval::ReferenceSetSelector::BandCollisionError, "collision")

      expect { Rake::Task["sway:eval:reference_set"].invoke }.to raise_error(SystemExit)
    end

    it "catches InsufficientNoTestimonyError by name and aborts rather than raising" do
      allow(Eval::ReferenceSetSelector).to receive(:call)
        .and_raise(Eval::ReferenceSetSelector::InsufficientNoTestimonyError, "not enough")

      expect { Rake::Task["sway:eval:reference_set"].invoke }.to raise_error(SystemExit)
    end

    it "catches InvalidSubstitutionError by name and aborts rather than raising" do
      allow(Eval::ReferenceSetSelector).to receive(:call)
        .and_raise(Eval::ReferenceSetSelector::InvalidSubstitutionError, "invalid")

      expect { Rake::Task["sway:eval:reference_set"].invoke }.to raise_error(SystemExit)
    end

    it "catches MissingDiffMarkdownError by name and aborts rather than raising" do
      allow(Eval::ReferenceSetSelector).to receive(:call)
        .and_raise(Eval::ReferenceSetSelector::MissingDiffMarkdownError, "missing diff")

      expect { Rake::Task["sway:eval:reference_set"].invoke }.to raise_error(SystemExit)
    end
  end
end
