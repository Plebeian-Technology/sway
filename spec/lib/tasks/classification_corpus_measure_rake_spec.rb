# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "sway:measure:classification_corpus" do
  let(:corpus_root) { Pathname.new(Dir.mktmpdir("classification-corpus")) }

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:measure:classification_corpus")
  end

  before do
    Rake::Task["sway:measure:classification_corpus"].reenable
    allow(Legislation::Paths).to receive(:hearings).and_return(corpus_root.join("hearings"))
    allow(Legislation::Paths).to receive(:attachments).and_return(corpus_root.join("attachments"))
  end

  after { FileUtils.remove_entry(corpus_root) }

  def write_corpus_fixture(sway_locale, id:, name:, text: nil)
    hearings = corpus_root.join("hearings", sway_locale)
    hearings.mkpath
    hearings.join("same-bill.json").write({attachments: [{id: id, name: name}]}.to_json)
    return if text.nil?

    attachments = corpus_root.join("attachments", sway_locale)
    attachments.mkpath
    attachments.join("attachment-#{id}.txt").write(text)
  end

  # @lat: [[testimony-attachment-rules#Corpus measurement keeps jurisdiction identity]]
  it "classifies identical names separately for each jurisdiction" do
    write_corpus_fixture("baltimore-maryland-united_states", id: 1, name: "Testimony.pdf", text: "position: a")
    write_corpus_fixture("congress-congress-united_states", id: 2, name: "Testimony.pdf", text: "position: b")

    expect { Rake::Task["sway:measure:classification_corpus"].invoke }
      .to output(a_string_including(
        "distinct locale/names:     2",
        "name-rule labels:          #{{testimony: 1, undecided: 1}.inspect}",
        "locale/names to the model: 1",
        "docs sent to the model:    1 #{{undecided: 1}.inspect}"
      )).to_stdout
  end

  it "keeps reused attachment and bill IDs separate and reads each jurisdiction's sidecar" do
    write_corpus_fixture("baltimore-maryland-united_states", id: 7, name: "Letter.pdf", text: "position: a")
    write_corpus_fixture("congress-congress-united_states", id: 7, name: "Letter.pdf", text: "#{"x" * 70} support")

    expect { Rake::Task["sway:measure:classification_corpus"].invoke }
      .to output(a_string_including(
        "attachments (locale/id):   2",
        "distinct locale/names:     2",
        "per-bill model docs:       [1, 1] (2 bills)",
        "with readable text:        2",
        "collapsed length:          min 11, median 78, max 78",
        "first-marker offset:       worst 71, p90 71"
      )).to_stdout
  end

  it "reports missing local text without borrowing the same ID from another jurisdiction" do
    write_corpus_fixture("baltimore-maryland-united_states", id: 7, name: "Letter.pdf", text: "position: a")
    write_corpus_fixture("congress-congress-united_states", id: 7, name: "Letter.pdf")

    expect { Rake::Task["sway:measure:classification_corpus"].invoke }
      .to output(a_string_including(
        "with readable text:        1",
        'unreadable (no text):      1 [["congress-congress-united_states", 7]]'
      )).to_stdout
  end

  it "ignores non-integer attachment IDs before constructing sidecar paths" do
    write_corpus_fixture("baltimore-maryland-united_states", id: "7/../../other", name: "Testimony.pdf")
    write_corpus_fixture("congress-congress-united_states", id: 7, name: "Letter.pdf", text: "position: a")

    expect { Rake::Task["sway:measure:classification_corpus"].invoke }
      .to output(a_string_including(
        "hearing artifacts read:    2",
        "attachments (locale/id):   1",
        "name-rule labels:          #{{undecided: 1}.inspect}",
        "with readable text:        1"
      )).to_stdout
  end
end
