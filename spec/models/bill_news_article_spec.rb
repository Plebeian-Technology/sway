# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: bill_news_articles
# Database name: primary
#
#  id                      :integer          not null, primary key
#  approved                :boolean          default(FALSE), not null
#  approved_at             :datetime
#  match_evidence          :text
#  match_kind              :string           default("direct"), not null
#  review_version          :integer          default(0), not null
#  stance                  :string
#  stance_version          :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  approved_by_id          :integer
#  bill_id                 :integer          not null
#  current_text_version_id :integer
#  news_article_id         :integer          not null
#  stance_by_id            :integer
#
# Indexes
#
#  index_bill_news_articles_on_approved_by_id               (approved_by_id)
#  index_bill_news_articles_on_bill_id                      (bill_id)
#  index_bill_news_articles_on_bill_id_and_approved         (bill_id,approved)
#  index_bill_news_articles_on_bill_id_and_news_article_id  (bill_id,news_article_id) UNIQUE
#  index_bill_news_articles_on_current_text_version_id      (current_text_version_id)
#  index_bill_news_articles_on_news_article_id              (news_article_id)
#  index_bill_news_articles_on_stance_by_id                 (stance_by_id)
#
# Foreign Keys
#
#  approved_by_id           (approved_by_id => users.id)
#  bill_id                  (bill_id => bills.id) ON DELETE => cascade
#  current_text_version_id  (current_text_version_id => news_article_text_versions.id) ON DELETE => restrict
#  news_article_id          (news_article_id => news_articles.id) ON DELETE => restrict
#  stance_by_id             (stance_by_id => users.id)
#
RSpec.describe BillNewsArticle, type: :model do
  # @lat: [[news-article-evidence#Article identity and bill association]]
  let(:sway_locale) { create(:sway_locale) }
  let(:bill) { create(:bill, sway_locale:, scheduled_release_date_utc: 1.day.ago.to_date) }

  describe "mandatory behavioral regression: multi-bill shared article review isolation" do
    it "shares article identity between two bills while keeping approval and stance bill-scoped" do
      article = create(:news_article)
      bill_1 = create(:bill, sway_locale:, scheduled_release_date_utc: 2.days.ago.to_date)
      bill_2 = create(:bill, sway_locale:, scheduled_release_date_utc: 3.days.ago.to_date)
      admin = create(:user, :sway_admin)

      bna_1 = create(:bill_news_article, bill: bill_1, news_article: article)
      bna_2 = create(:bill_news_article, bill: bill_2, news_article: article)

      expect(bna_1.approved).to be false
      expect(bna_1.review_version).to eq(0)
      expect(bna_1.stance).to be_nil
      expect(bna_1.stance_version).to eq(0)

      expect(bna_2.approved).to be false
      expect(bna_2.review_version).to eq(0)
      expect(bna_2.stance).to be_nil
      expect(bna_2.stance_version).to eq(0)

      bna_1.approve!(by: admin)
      bna_1.set_stance!("support", by: admin)

      bna_1.reload
      expect(bna_1.approved).to be true
      expect(bna_1.approved_by).to eq(admin)
      expect(bna_1.approved_at).to be_present
      expect(bna_1.review_version).to eq(1)
      expect(bna_1.stance).to eq("support")
      expect(bna_1.stance_by).to eq(admin)
      expect(bna_1.stance_version).to eq(1)

      bna_2.reload
      expect(bna_2.approved).to be false
      expect(bna_2.approved_by).to be_nil
      expect(bna_2.approved_at).to be_nil
      expect(bna_2.review_version).to eq(0)
      expect(bna_2.stance).to be_nil
      expect(bna_2.stance_by).to be_nil
      expect(bna_2.stance_version).to eq(0)
    end
  end

  describe "validations" do
    it "is valid with factory defaults" do
      article = build(:news_article)
      bna = build(:bill_news_article, bill:, news_article: article)
      expect(bna).to be_valid
    end

    it "requires bill" do
      article = build(:news_article)
      bna = build(:bill_news_article, bill: nil, news_article: article)
      expect(bna).not_to be_valid
      expect(bna.errors[:bill]).to be_present
    end

    it "requires news_article" do
      bna = build(:bill_news_article, bill:, news_article: nil)
      expect(bna).not_to be_valid
      expect(bna.errors[:news_article]).to be_present
    end

    it "enforces uniqueness of news_article_id scoped to bill_id" do
      article = create(:news_article)
      create(:bill_news_article, bill:, news_article: article)
      duplicate = build(:bill_news_article, bill:, news_article: article)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:news_article_id]).to include("has already been taken")
    end

    it "allows the same news_article on a different bill" do
      article = create(:news_article)
      other_bill = create(:bill, sway_locale:, scheduled_release_date_utc: 5.days.ago.to_date)
      create(:bill_news_article, bill:, news_article: article)
      other_bna = build(:bill_news_article, bill: other_bill, news_article: article)

      expect(other_bna).to be_valid
    end

    describe "default column values" do
      it "defaults approved to false, review_version to 0, stance_version to 0, and match_kind to direct" do
        article = build(:news_article)
        bna = described_class.new(bill:, news_article: article)
        expect(bna.approved).to be false
        expect(bna.review_version).to eq(0)
        expect(bna.stance_version).to eq(0)
        expect(bna.stance).to be_nil
        expect(bna.match_kind).to eq("direct")
      end
    end

    describe "stance validation" do
      it "allows support, oppose, and nil" do
        article = build(:news_article)
        [nil, "support", "oppose"].each do |valid_stance|
          bna = build(:bill_news_article, bill:, news_article: article, stance: valid_stance)
          expect(bna).to be_valid
        end
      end

      it "rejects invalid stances such as neutral, abstain, or arbitrary strings" do
        article = build(:news_article)
        %w[neutral abstain for against invalid].each do |bad_stance|
          bna = build(:bill_news_article, bill:, news_article: article, stance: bad_stance)
          expect(bna).not_to be_valid
          expect(bna.errors[:stance]).to be_present
        end
      end
    end

    describe "match_kind validation" do
      it "allows direct and context" do
        article = build(:news_article)
        %w[direct context].each do |valid_kind|
          bna = build(:bill_news_article, bill:, news_article: article, match_kind: valid_kind)
          expect(bna).to be_valid
        end
      end

      it "rejects missing or invalid match_kind" do
        article = build(:news_article)
        [nil, "", "tangential", "unrelated"].each do |bad_kind|
          bna = build(:bill_news_article, bill:, news_article: article, match_kind: bad_kind)
          expect(bna).not_to be_valid
          expect(bna.errors[:match_kind]).to be_present
        end
      end
    end

    describe "version numericality" do
      it "requires non-negative integer for review_version and stance_version" do
        article = build(:news_article)
        bna = build(:bill_news_article, bill:, news_article: article, review_version: -1)
        expect(bna).not_to be_valid

        bna2 = build(:bill_news_article, bill:, news_article: article, stance_version: -1)
        expect(bna2).not_to be_valid
      end
    end

    describe "immutability of bill_id" do
      it "rejects changing bill_id on a persisted record" do
        article = create(:news_article)
        bna = create(:bill_news_article, bill:, news_article: article)
        other_bill = create(:bill, sway_locale:, scheduled_release_date_utc: 10.days.ago.to_date)

        bna.bill = other_bill
        expect(bna).not_to be_valid
        expect(bna.errors[:bill_id]).to include("cannot be changed once persisted")
      end
    end
  end

  describe "associations" do
    it "belongs to bill" do
      article = create(:news_article)
      bna = create(:bill_news_article, bill:, news_article: article)
      expect(bna.bill).to eq(bill)
    end

    it "belongs to news_article" do
      article = create(:news_article)
      bna = create(:bill_news_article, bill:, news_article: article)
      expect(bna.news_article).to eq(article)
    end

    it "optionally belongs to approved_by (User)" do
      admin = create(:user, :sway_admin)
      article = create(:news_article)
      bna = create(:bill_news_article, :approved, bill:, news_article: article, approved_by: admin)
      expect(bna.approved_by).to eq(admin)
    end

    it "optionally belongs to stance_by (User)" do
      admin = create(:user, :sway_admin)
      article = create(:news_article)
      bna = create(:bill_news_article, :support, bill:, news_article: article, stance_by: admin)
      expect(bna.stance_by).to eq(admin)
    end
  end

  describe "delegation" do
    it "delegates sway_locale and legislative_session to bill" do
      article = build(:news_article)
      bna = build(:bill_news_article, bill:, news_article: article)
      expect(bna.sway_locale).to eq(bill.sway_locale)
      expect(bna.legislative_session).to eq(bill.legislative_session)
    end
  end

  describe "lifecycle methods" do
    let(:admin) { create(:user, :sway_admin) }

    describe "#approve!" do
      it "updates approved, approved_by, approved_at, and increments review_version" do
        article = create(:news_article)
        bna = create(:bill_news_article, bill:, news_article: article)
        expect { bna.approve!(by: admin) }.to change(bna, :review_version).by(1)
        bna.reload
        expect(bna.approved).to be true
        expect(bna.approved_by).to eq(admin)
        expect(bna.approved_at).to be_present
      end
    end

    describe "#withdraw_approval!" do
      it "sets approved to false, updates approved_by, and increments review_version" do
        article = create(:news_article)
        bna = create(:bill_news_article, bill:, news_article: article)
        bna.approve!(by: admin)
        expect { bna.withdraw_approval!(by: admin) }.to change(bna, :review_version).by(1)
        bna.reload
        expect(bna.approved).to be false
        expect(bna.approved_by).to eq(admin)
      end
    end

    describe "#set_stance!" do
      it "sets valid stance, stance_by, and increments stance_version" do
        article = create(:news_article)
        bna = create(:bill_news_article, bill:, news_article: article)
        expect { bna.set_stance!("support", by: admin) }.to change(bna, :stance_version).by(1)
        bna.reload
        expect(bna.stance).to eq("support")
        expect(bna.stance_by).to eq(admin)
      end

      it "raises ArgumentError when setting an invalid stance" do
        article = create(:news_article)
        bna = create(:bill_news_article, bill:, news_article: article)
        expect { bna.set_stance!("neutral", by: admin) }.to raise_error(ArgumentError, /Invalid stance/)
      end
    end

    describe "#clear_stance!" do
      it "clears stance, sets stance_by, and increments stance_version" do
        article = create(:news_article)
        bna = create(:bill_news_article, bill:, news_article: article)
        bna.set_stance!("oppose", by: admin)
        expect { bna.clear_stance!(by: admin) }.to change(bna, :stance_version).by(1)
        bna.reload
        expect(bna.stance).to be_nil
        expect(bna.stance_by).to eq(admin)
      end
    end
  end

  describe "scopes" do
    describe ".approved and .unapproved" do
      it "filters records by approved state" do
        article = create(:news_article)
        approved_bna = create(:bill_news_article, :approved, bill:, news_article: article)
        unapproved_bna = create(:bill_news_article, bill:, news_article: create(:news_article), approved: false)

        expect(described_class.approved).to include(approved_bna)
        expect(described_class.approved).not_to include(unapproved_bna)
        expect(described_class.unapproved).to include(unapproved_bna)
        expect(described_class.unapproved).not_to include(approved_bna)
      end
    end

    describe ".with_stance" do
      it "returns records where stance is not nil" do
        support_bna = create(:bill_news_article, :support, bill:, news_article: create(:news_article))
        oppose_bna = create(:bill_news_article, :oppose, bill:, news_article: create(:news_article))
        unapproved_bna = create(:bill_news_article, bill:, news_article: create(:news_article), approved: false)

        expect(described_class.with_stance).to include(support_bna, oppose_bna)
        expect(described_class.with_stance).not_to include(unapproved_bna)
      end
    end

    describe ".supporting / .support" do
      it "returns records where stance is support" do
        support_bna = create(:bill_news_article, :support, bill:, news_article: create(:news_article))
        oppose_bna = create(:bill_news_article, :oppose, bill:, news_article: create(:news_article))

        expect(described_class.supporting).to include(support_bna)
        expect(described_class.supporting).not_to include(oppose_bna)
        expect(described_class.support).to include(support_bna)
      end
    end

    describe ".opposing / .oppose" do
      it "returns records where stance is oppose" do
        support_bna = create(:bill_news_article, :support, bill:, news_article: create(:news_article))
        oppose_bna = create(:bill_news_article, :oppose, bill:, news_article: create(:news_article))

        expect(described_class.opposing).to include(oppose_bna)
        expect(described_class.opposing).not_to include(support_bna)
        expect(described_class.oppose).to include(oppose_bna)
      end
    end

    describe ".direct_matches / .direct_match" do
      it "returns records with match_kind direct" do
        article = create(:news_article)
        direct_bna = create(:bill_news_article, :approved, bill:, news_article: article)
        context_bna = create(:bill_news_article, :context_match, bill:, news_article: create(:news_article))

        expect(described_class.direct_matches).to include(direct_bna)
        expect(described_class.direct_matches).not_to include(context_bna)
        expect(described_class.direct_match).to include(direct_bna)
      end
    end

    describe ".context_matches / .context_match" do
      it "returns records with match_kind context" do
        article = create(:news_article)
        direct_bna = create(:bill_news_article, :approved, bill:, news_article: article)
        context_bna = create(:bill_news_article, :context_match, bill:, news_article: create(:news_article))

        expect(described_class.context_matches).to include(context_bna)
        expect(described_class.context_matches).not_to include(direct_bna)
        expect(described_class.context_match).to include(context_bna)
      end
    end
  end

  describe "current_text_version association and cross-article validation" do
    let(:article) { create(:news_article) }

    it "belongs to current_text_version optionally" do
      bna = create(:bill_news_article, bill:, news_article: article)
      expect(bna.current_text_version).to be_nil

      version = create(:news_article_text_version, news_article: article)
      bna.update!(current_text_version: version)

      expect(bna.reload.current_text_version).to eq(version)
    end

    it "allows assigning current_text_version that belongs to the same news_article" do
      bna = create(:bill_news_article, bill:, news_article: article)
      version = create(:news_article_text_version, news_article: article)
      bna.current_text_version = version
      expect(bna).to be_valid
    end

    it "rejects assigning current_text_version belonging to a different news_article" do
      bna = create(:bill_news_article, bill:, news_article: article)
      other_art = create(:news_article)
      foreign_version = create(:news_article_text_version, news_article: other_art)
      bna.current_text_version = foreign_version

      expect(bna).not_to be_valid
      expect(bna.errors[:current_text_version]).to include("must belong to the associated news article")
    end

    it "allows clearing current_text_version back to nil" do
      bna = create(:bill_news_article, bill:, news_article: article)
      version = create(:news_article_text_version, news_article: article)
      bna.update!(current_text_version: version)
      expect(bna.current_text_version).to eq(version)

      bna.update!(current_text_version: nil)
      expect(bna.reload.current_text_version).to be_nil
    end

    it "replacing current_text_version does not alter approved, review_version, stance, or stance_version" do
      bna = create(:bill_news_article, bill:, news_article: article)
      admin = create(:user, :sway_admin)
      bna.approve!(by: admin)
      bna.set_stance!("support", by: admin)

      version_1 = create(:news_article_text_version, news_article: article, text: "First text")
      bna.update!(current_text_version: version_1)

      expect(bna.approved).to be true
      expect(bna.review_version).to eq(1)
      expect(bna.stance).to eq("support")
      expect(bna.stance_version).to eq(1)

      version_2 = create(:news_article_text_version, news_article: article, text: "Replacement text")
      bna.update!(current_text_version: version_2)

      bna.reload
      expect(bna.current_text_version).to eq(version_2)
      expect(bna.approved).to be true
      expect(bna.review_version).to eq(1)
      expect(bna.stance).to eq("support")
      expect(bna.stance_version).to eq(1)
    end
  end

  describe "eligibility predicates and scopes" do
    let(:article) { create(:news_article) }

    describe "#link_eligible? / #eligible_for_link?" do
      it "returns true if approved, even when textless" do
        bna = build(:bill_news_article, :approved, bill:, news_article: article, current_text_version: nil)
        expect(bna.link_eligible?).to be true
        expect(bna.eligible_for_link?).to be true
      end

      it "returns false if unapproved" do
        text_version = create(:news_article_text_version, :extracted, news_article: article)
        bna = build(:bill_news_article, bill:, news_article: article, approved: false, current_text_version: text_version)
        expect(bna.link_eligible?).to be false
        expect(bna.eligible_for_link?).to be false
      end
    end

    describe "#synthesis_eligible? / #eligible_for_synthesis?" do
      it "returns true when approved and has a current_text_version with usable text" do
        text_version = create(:news_article_text_version, :extracted, news_article: article)
        bna = build(:bill_news_article, :approved, bill:, news_article: article, current_text_version: text_version)
        expect(bna.synthesis_eligible?).to be true
        expect(bna.eligible_for_synthesis?).to be true
      end

      it "returns false when approved but textless" do
        bna = build(:bill_news_article, :approved, bill:, news_article: article, current_text_version: nil)
        expect(bna.synthesis_eligible?).to be false
        expect(bna.eligible_for_synthesis?).to be false
      end

      it "returns false when approved but current_text_version is paywalled or failed" do
        paywalled_version = create(:news_article_text_version, :paywalled, news_article: article)
        bna = build(:bill_news_article, :approved, bill:, news_article: article, current_text_version: paywalled_version)
        expect(bna.synthesis_eligible?).to be false
        expect(bna.eligible_for_synthesis?).to be false
      end

      it "returns false when unapproved, even if usable text exists" do
        text_version = create(:news_article_text_version, :extracted, news_article: article)
        bna = build(:bill_news_article, bill:, news_article: article, approved: false, current_text_version: text_version)
        expect(bna.synthesis_eligible?).to be false
        expect(bna.eligible_for_synthesis?).to be false
      end
    end

    describe "scopes: .link_eligible / .eligible_for_link and .synthesis_eligible / .eligible_for_synthesis" do
      it "filters link_eligible and synthesis_eligible records correctly" do
        text_version = create(:news_article_text_version, :extracted, news_article: article)
        paywalled_article = create(:news_article)
        paywalled_ver = create(:news_article_text_version, :paywalled, news_article: paywalled_article)
        unapproved_article = create(:news_article)
        unapproved_ver = create(:news_article_text_version, :extracted, news_article: unapproved_article)

        approved_text_bna = create(:bill_news_article, :approved, bill:, news_article: article, current_text_version: text_version)
        approved_textless_bna = create(:bill_news_article, :approved, bill:, news_article: create(:news_article), current_text_version: nil)
        approved_paywalled_bna = create(:bill_news_article, :approved, bill:, news_article: paywalled_article, current_text_version: paywalled_ver)
        unapproved_bna = create(:bill_news_article, bill:, news_article: unapproved_article, approved: false, current_text_version: unapproved_ver)

        expect(described_class.link_eligible).to include(approved_text_bna, approved_textless_bna, approved_paywalled_bna)
        expect(described_class.link_eligible).not_to include(unapproved_bna)
        expect(described_class.eligible_for_link).to include(approved_text_bna, approved_textless_bna, approved_paywalled_bna)

        expect(described_class.synthesis_eligible).to include(approved_text_bna)
        expect(described_class.synthesis_eligible).not_to include(approved_textless_bna, approved_paywalled_bna, unapproved_bna)
        expect(described_class.eligible_for_synthesis).to include(approved_text_bna)
      end

      it "excludes articles whose text is whitespace only from eligible_for_synthesis" do
        whitespace_art = create(:news_article)
        whitespace_ver = create(:news_article_text_version, :extracted, news_article: whitespace_art, text: "placeholder")
        ActiveRecord::Base.connection.execute("UPDATE news_article_text_versions SET text = '   \t  \n  ' WHERE id = #{whitespace_ver.id}")

        whitespace_bna = create(:bill_news_article, :approved, bill: bill, news_article: whitespace_art, current_text_version: whitespace_ver)

        expect(described_class.eligible_for_synthesis).not_to include(whitespace_bna)
        expect(described_class.synthesis_eligible).not_to include(whitespace_bna)
        expect(described_class.eligible_for_link).to include(whitespace_bna)
        expect(whitespace_bna.reload.eligible_for_synthesis?).to be false
        expect(whitespace_bna.synthesis_eligible?).to be false
      end
    end
  end
end
