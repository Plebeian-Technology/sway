# frozen_string_literal: true

require "rails_helper"

# One place for what a chamber says about the person in it, so the
# seeder and the term-length repair cannot answer it differently.
RSpec.describe CongressChamber do
  describe ".title_for" do
    it "addresses a member of the Senate as a senator" do
      expect(described_class.title_for("Senate")).to eq("Sen.")
    end

    it "addresses a member of the House as a representative" do
      expect(described_class.title_for("House of Representatives")).to eq("Rep.")
    end

    it "addresses the President as President, whatever their chamber reads" do
      expect(described_class.title_for("White House", president: true)).to eq("Pres.")
    end

    it "falls back to representative when the chamber is missing" do
      expect(described_class.title_for(nil)).to eq("Rep.")
    end

    # The roster writes "White House" where a chamber would go. Read as a
    # chamber it is not the Senate, so the President came out a representative
    # — which is what his term row said in the production copy.
    it "knows the President from the roster's own words, with no flag passed" do
      expect(described_class.title_for("White House")).to eq("Pres.")
    end
  end

  describe ".term_years_for" do
    it "runs a Senate term six years" do
      expect(described_class.term_years_for("Sen.")).to eq(6)
    end

    it "runs a House term two years" do
      expect(described_class.term_years_for("Rep.")).to eq(2)
    end

    it "runs a presidential term four years" do
      expect(described_class.term_years_for("Pres.")).to eq(4)
    end

    # The shorter of the two, so an unexpected title ends a term early rather
    # than keeping somebody in office who has left.
    it "treats an unrecognised title as a seat in the House" do
      expect(described_class.term_years_for("Council Member")).to eq(2)
      expect(described_class.term_years_for(nil)).to eq(2)
    end
  end
end
