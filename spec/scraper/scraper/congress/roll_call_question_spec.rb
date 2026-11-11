# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::Congress::RollCallQuestion do
  def asked(chamber, question, title = nil)
    described_class.new(chamber: chamber, question: question, title: title)
  end

  # Counted from the published record on 2026-08-12: 120 House roll calls of
  # 2025, and the Senate's vote lists for 119-1 (1298 votes) and 118-2 (339).
  describe "the House" do
    # 41 of those 120 roll calls passed a bill under suspension against 33 by
    # plain passage. Accepting only "On Passage" would refuse most of them.
    [
      "On Passage",
      "On Motion to Suspend the Rules and Pass",
      "On Motion to Suspend the Rules and Pass, as Amended",
      "On Agreeing to the Resolution",
      "On Agreeing to the Resolution, as Amended",
      "On Motion to Concur in the Senate Amendment",
      "On Agreeing to the Conference Report",
      "On Passage, Objections of the President Notwithstanding"
    ].each do |question|
      it "counts #{question.inspect} as a position on the bill" do
        expect(asked(:house, question)).to be_counts_as_position
      end
    end

    [
      "On Ordering the Previous Question",
      "On Motion to Recommit",
      "On Motion to Commit with Instructions",
      "On Motion to Table",
      "On Agreeing to the Amendment",
      "Call by States",
      "Call of the House",
      "Election of the Speaker"
    ].each do |question|
      it "refuses #{question.inspect}" do
        expect(asked(:house, question)).not_to be_counts_as_position
      end
    end

    # A motion to recommit is normally a vote against the bill's supporters,
    # and it reads as a bill vote because it names the bill.
    it "knows the questions it refuses" do
      expect(asked(:house, "On Motion to Recommit")).to be_known
    end

    # A concurrence that adds its own amendment sends the bill back to the
    # Senate, so it is a vote on the new text, not the bill as it will stand.
    it "refuses a concurrence that carries its own amendment" do
      amended = asked(:house, "On Motion to Concur in the Senate Amendment with an Amendment")

      expect(amended).not_to be_counts_as_position
      expect(amended).to be_known
    end

    it "says so when the question is one it has never seen" do
      expect(asked(:house, "On Doing Something New")).not_to be_known
    end
  end

  describe "the Senate" do
    [
      "On Passage of the Bill",
      "On the Nomination",
      "On the Joint Resolution",
      "On the Resolution",
      "On the Concurrent Resolution",
      "On Overriding the Veto",
      "On Cloture on the Motion to Proceed"
    ].each do |question|
      it "counts #{question.inspect} as a position on the bill" do
        expect(asked(:senate, question)).to be_counts_as_position
      end
    end

    # Cloture is 478 of the 1298 Senate roll calls of one session — the single
    # most common question, and the one a member most often answers differently
    # from passage.
    [
      "On the Motion to Proceed",
      "On the Motion to Table",
      "On the Motion to Reconsider",
      "On the Motion to Discharge",
      "On the Motion to Recommit",
      "On the Motion to Refer",
      "On the Motion to Adjourn",
      "On the Decision of the Chair",
      "On the Point of Order",
      "On the Amendment"
    ].each do |question|
      it "refuses #{question.inspect}" do
        expect(asked(:senate, question)).not_to be_counts_as_position
      end
    end

    # Real record: roll call 331 of the 118th Congress, second session. Cloture
    # on a nomination, so the document name matches a nomination bill and only
    # the question tells the two votes apart.
    it "counts cloture as a position even when the record names a nomination" do
      cloture = asked(:senate, "On the Cloture Motion",
        "Motion to Invoke Cloture: Serena Raquel Murillo to be U.S. District Judge")

      expect(cloture).to be_counts_as_position
      expect(cloture).to be_known
    end

    # Bill s1111 is roll call 200 of 2024. Refusing the bare question would
    # drop its 55 real votes.
    it "counts a bare motion when the title names a concurrence" do
      expect(asked(:senate, "On the Motion", "Motion to Concur in the House Amendments to S. 870"))
        .to be_counts_as_position
    end

    # A concurrence that adds its own amendment sends the bill back to the
    # House, so it is a vote on the new text, not on the bill as it will stand.
    it "refuses a concurrence that carries its own amendment" do
      amended = asked(:senate, "On the Motion",
        "Motion to Concur in the House Amendment to the Senate Amendment with a Further Amendment")

      expect(amended).not_to be_counts_as_position
      expect(amended).to be_known
    end

    it "refuses a bare motion with no title" do
      expect(asked(:senate, "On the Motion")).not_to be_counts_as_position
    end

    it "refuses a bare motion whose title is some other motion" do
      expect(asked(:senate, "On the Motion", "Motion to Table Amendment No. 3114"))
        .not_to be_counts_as_position
    end

    # The Senate's published vote lists put in brackets what the XML puts in
    # the title. Both shapes are real, so both are read the same way.
    it "reads a bracketed concurrence the same as a title" do
      expect(asked(:senate, "On the Motion (Motion to Concur in the House Amendments to S. 870)"))
        .to be_counts_as_position
    end

    it "still refuses a bracketed motion that is not a concurrence" do
      bracketed = asked(:senate, "On the Motion (Motion to Close the Doors)")

      expect(bracketed).not_to be_counts_as_position
      expect(bracketed).to be_known
    end
  end

  it "refuses a chamber it has no rules for" do
    expect(asked(:assembly, "On Passage")).not_to be_counts_as_position
  end

  # Asked with a phrase only the Senate list holds, so a chamber that borrowed
  # that list would claim to recognise it.
  it "does not borrow another chamber's list to recognise a question" do
    expect(asked(:assembly, "On the Cloture Motion")).not_to be_known
  end

  it "refuses a record that states no question" do
    expect(asked(:senate, nil)).not_to be_counts_as_position
  end

  # The clerk's own spacing varies between records.
  it "reads a question the same however it is spaced" do
    expect(asked(:house, "  On   Passage \n")).to be_counts_as_position
  end
end
