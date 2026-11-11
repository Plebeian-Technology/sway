# frozen_string_literal: true

require "rails_helper"

# Stages 1 and 2 of the testimony filter. Every name here is a REAL
# Legistar attachment name from live-API surveys — pinning behavior
# against names Baltimore staff actually type.
RSpec.describe Testimony::NameRules do
  describe ".classify" do
    # @lat: [[testimony-attachment-rules#Testimony attachment rules#Locale regression coverage]]
    it "leaves every Baltimore rule family undecided outside Baltimore" do
      names = ["Public Testimony", "Enrolled", "Signed", "Signed Petition of Support", "Voting Record"]
      locales = ["maryland-maryland-united_states", "united_states-united_states-united_states", "annapolis-maryland-united_states", "baltimore-ohio-united_states", nil]
      locales.each do |locale|
        names.each do |name|
          expect(described_class.classify(name, sway_locale: locale)).to eq(:undecided)
        end
      end
    end

    context "stage 1 — obviously testimony" do
      # The name says "testimony" outright.
      it "classifies an explicit testimony document" do
        expect(described_class.classify("10.16.25 Public Testimony 25-0064", sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
      end

      # An underscore counts as a word character, so the \b word boundary does
      # not match between "Testimony" and "_25". An earlier draft of the filter
      # could not see this exact name.
      it "classifies a name whose separators are underscores" do
        expect(described_class.classify("Health Care for the Homeless Testimony_25-0062.pdf", sway_locale: "baltimore-maryland-united_states"))
          .to eq(:testimony)
      end

      it "classifies stance-bearing names that never say 'testimony'" do
        expect(described_class.classify("100 Holliday Street - Community Letter of Support", sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
        expect(described_class.classify("2025-0060 Alex Morgan Oppose", sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
        expect(described_class.classify("25-0060 Jordan Taylor Comment Only", sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
        expect(described_class.classify("MG Opposition 25-0065.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
        expect(described_class.classify("25-0053 Highlandtown Community Association .pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
      end

      # This name is why the bill-text patterns must be precise rather than
      # loose keyword matches: it contains "Amendment", but it is a resident
      # stating a position, not an amendment document.
      it "classifies a stance name that merely mentions an amendment" do
        expect(described_class.classify("25-0060 Casey Rivera Support with Amendment", sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
      end

      # Proves no pattern is redundant — each one must have an example
      # name that only it matches, not one already covered by another pattern.
      it "gives every testimony pattern a name only it decides" do
        # Real Legistar names, or small variations this file allows. Public
        # Comment and In Favor need a name of their own since the corpus
        # only carries them inside longer names another pattern decides.
        names = [
          "10.16.25 Public Testimony 25-0064",
          "25-0064 Public Comment",
          "25-0060 Jordan Taylor Comment Only",
          "2025-0060 Alex Morgan Oppose",
          "100 Holliday Street - Community Letter of Support",
          "Letter in Favor 25-0064",
          "25-0053 Highlandtown Community Association .pdf"
        ]
        patterns = described_class::TESTIMONY_PATTERNS

        patterns.each do |pattern|
          others = patterns - [pattern]
          own = names.find do |name|
            normalized = name.downcase
            pattern.match?(normalized) && others.none? { |sibling| sibling.match?(normalized) }
          end

          expect(own).not_to be_nil, "no name in this example is decided by #{pattern.inspect} alone"
        end
      end
    end

    context "stage 2 — obviously bill text (non-overridable)" do
      it "classifies reader and reprint markers" do
        expect(described_class.classify("25-0064~3rd Reader", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("cc25-0064(1)~1st (LUT)", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("cc25-0064(1)~1st (Gray)", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
      end

      # `Law 25-0064` is deliberately NOT here — see the Law Department
      # example in the stage-3 hand-off section below.
      it "classifies enacted-law and signature artifacts" do
        expect(described_class.classify("25-0064 Signed", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("25-0064 Enrolled", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("25-0064 Engrossed", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("Ord.25-123", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
      end

      # A guard on the edge of the rule: every genuine bill-text name on
      # real matter 10122 (bill 25-0064), the set that must stay denied now
      # that Law NN-NNNN is not. Read out of the reference cassette.
      it "keeps denying every genuine bill-text name on the reference matter" do
        expect(described_class.classify("25-0064~3rd Reader", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("25-0064~1st Reader.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("cc25-0064(1)~1st (LUT)", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("25-0064 Signed", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("Ord.25-063 tc", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
      end

      it "classifies amendment documents where the amendment IS the subject" do
        expect(described_class.classify("25-0100~Unoff'l Reprint. Highlighted Amdts", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("Amendment 1", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
      end

      # The feature's hard rule: treating bill text as testimony breaks the
      # requirement, while missing real testimony only weakens the feature.
      # So bill text beats an allowlist hit, always.
      it "beats an allowlist hit — deny wins for bill text" do
        expect(described_class.classify("25-0064~3rd Reader Testimony", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("25-0064 Enrolled - Letter of Support", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
      end

      # The same guard as on the testimony list: a pattern nothing decides
      # alone can be narrowed or deleted with the whole file green. It
      # matters most here, since this list cannot be overridden.
      it "gives every bill-text pattern a name only it decides" do
        names = [
          "cc25-0064(1)~1st (LUT)",
          "25-0064 1st Reader",
          "25-0064 Enrolled",
          "25-0064 Engrossed",
          "25-0100 Unoff'l Reprint"
        ]
        patterns = described_class::BILL_TEXT_PATTERNS

        patterns.each do |pattern|
          others = patterns - [pattern]
          own = names.find do |name|
            normalized = name.downcase
            pattern.match?(normalized) && others.none? { |sibling| sibling.match?(normalized) }
          end

          expect(own).not_to be_nil, "no name in this example is decided by #{pattern.inspect} alone"
        end
      end
    end

    # Three of nine bill-text patterns weren't tied to Baltimore's naming.
    # A :bill_text verdict skips the allowlist, cache and stage 3, so wrong
    # matches dropped documents permanently.
    context "stage 2c — ambiguous bill text (recoverable via stage 3)" do
      # Each name below misfired under the patterns as they shipped: all eight
      # came back :bill_text, and every one is a document with "Testimony" or
      # "Letter of Support" in its name.
      it "hands an amendment name that also reads as testimony to stage 3" do
        expect(described_class.classify("Coalition Testimony re Amendment 3.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:ambiguous_bill_text)
        expect(described_class.classify("Amendment Testimony from ACLU.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:ambiguous_bill_text)
        expect(described_class.classify("Testimony supporting amendments.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:ambiguous_bill_text)
      end

      it "hands a 'reader' name that also reads as testimony to stage 3" do
        expect(described_class.classify("Baltimore Readers Alliance Testimony.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:ambiguous_bill_text)
        expect(described_class.classify("Testimony - Sunday Reader Series.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:ambiguous_bill_text)
        expect(described_class.classify("Letter of Support - Reader Program.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:ambiguous_bill_text)
      end

      it "hands a 'signed' name that also reads as testimony to stage 3" do
        expect(described_class.classify("Signed Petition of Support.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:ambiguous_bill_text)
        expect(described_class.classify("Signed community letter of support.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:ambiguous_bill_text)
      end

      # A FOURTH pattern of the same shape, missed the first time:
      # ord(inance)?\s*\d matched testifying ABOUT an ordinance, yet sat in
      # the un-overridable list, classifying it :bill_text permanently.
      it "hands an ordinance name that also reads as testimony to stage 3" do
        expect(described_class.classify("Testimony in Support of Ordinance 25-0064.pdf", sway_locale: "baltimore-maryland-united_states"))
          .to eq(:ambiguous_bill_text)
        expect(described_class.classify("BUILD Testimony - Ordinance 25-0064", sway_locale: "baltimore-maryland-united_states")).to eq(:ambiguous_bill_text)
        expect(described_class.classify("Ord.25-063 tc Letter of Support", sway_locale: "baltimore-maryland-united_states")).to eq(:ambiguous_bill_text)
        expect(described_class.classify("Opposition to Ordinance 25-0061.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:ambiguous_bill_text)
      end

      # Third copy of the same guard, so all four pattern lists carry it.
      # Ord.25-063 tc deliberately isn't the ordinance pattern's own name,
      # since \s* doesn't match the full stop.
      it "gives every ambiguous bill-text pattern a name only it decides" do
        names = [
          "3rd Reader",
          "25-0064 Signed",
          "Amendment 1",
          "Ordinance 25-0064"
        ]
        patterns = described_class::AMBIGUOUS_BILL_TEXT_PATTERNS

        patterns.each do |pattern|
          others = patterns - [pattern]
          own = names.find do |name|
            normalized = name.downcase
            pattern.match?(normalized) && others.none? { |sibling| sibling.match?(normalized) }
          end

          expect(own).not_to be_nil, "no name in this example is decided by #{pattern.inspect} alone"
        end
      end

      # The way back depends on the allowlist; it is not automatic. With no
      # testimony hit, these are still bill text and still denied.
      it "still denies an ambiguous name with no allowlist hit" do
        expect(described_class.classify("25-0064 Signed", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("Amendment 1", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("25-0100~Unoff'l Reprint. Highlighted Amdts", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("3rd Reader", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        # The enacted-law names that stay denied: all five ordinance-matching
        # names in the recording have this shape, none carries a testimony
        # word — the change costs the recorded set nothing.
        expect(described_class.classify("Ord.25-063 tc", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("Ord. 25-061 tc revised (003)", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("Ord.25-123", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("Ordinance 25-0064", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
      end

      # The hard rule is untouched for the patterns tied to Baltimore's naming:
      # an allowlist hit never rescues one of those, no matter what else the
      # name says.
      it "does not extend the recovery path to an ANCHORED bill-text match" do
        expect(described_class.classify("25-0064~3rd Reader Testimony", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("25-0064 Enrolled - Letter of Support", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("Engrossed 25-0064 Public Testimony", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("25-0100 Reprint Testimony", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("cc25-0064(1)~1st (LUT) Testimony", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
        expect(described_class.classify("25-0064 1st Reader Testimony", sway_locale: "baltimore-maryland-united_states")).to eq(:bill_text)
      end
    end

    context "stage 2 — procedural (overridable by the allowlist)" do
      # One name per PROCEDURAL_PATTERNS entry, each reaching :procedural
      # through exactly one. Six had no name at all, including one that
      # A19-10 made carry hearing notes' job (A20-07).
      let(:procedural_names) do
        [
          "Voting Record 25-0064",
          "25-0064 Attendance",
          "Newspaper Advertisement",
          "Notice of Hearing 25-0064",
          "Hearing Packet 25-0064",
          "25-0064 Synopsis",
          "BDC Presentation",
          "BDC PowerPoint",
          "Transmittal Letter",
          "25-0064 Memorandum",
          "Site Plat",
          "Site Map",
          "Floor Plan",
          "Statement of Intent",
          "Hearing Notes 25-0064",
          "Lead Paint Case Study",
          "25-0064 Stamped",
          "Request to Return"
        ]
      end

      it "classifies procedural documents" do
        procedural_names.each do |name|
          expect(described_class.classify(name, sway_locale: "baltimore-maryland-united_states")).to eq(:procedural), "expected #{name.inspect} to be procedural"
        end
      end

      # THE GUARD THE LIST ABOVE CAN'T BE ON ITS OWN: a pattern with no
      # name, or one whose only name a sibling also matches, can be
      # narrowed or deleted with the file still green.
      it "gives every procedural pattern a name only it decides" do
        patterns = described_class::PROCEDURAL_PATTERNS

        patterns.each do |pattern|
          others = patterns - [pattern]
          own = procedural_names.find do |name|
            normalized = name.downcase
            pattern.match?(normalized) && others.none? { |sibling| sibling.match?(normalized) }
          end

          expect(own).not_to be_nil, "no name in procedural_names is decided by #{pattern.inspect} alone"
        end
      end

      # Seen in real data — someone really typed it this way.
      it "classifies the observed 'Voiting Record' typo" do
        expect(described_class.classify("Voiting Record", sway_locale: "baltimore-maryland-united_states")).to eq(:procedural)
      end

      # A packet whose name also announces testimony probably CONTAINS
      # testimony, and denying it would lose evidence for no safety gain.
      it "lets an allowlist hit win over a procedural denial" do
        expect(described_class.classify("Hearing Packet with Public Testimony", sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
      end
    end

    context "stage 3 hand-off — undecided" do
      # Agency documents carry an organization's position, exactly what
      # this feature collects, so they must NOT be denied. They carry no
      # allowlist keyword, which is what the LLM stage is for.
      it "leaves agency documents undecided for the LLM" do
        expect(described_class.classify("DOF 25-0064", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
        expect(described_class.classify("DHCD 25-0053", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
        expect(described_class.classify("BCFD 25-0060", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
        expect(described_class.classify("Planning Commission 25-0064", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
      end

      # Keyword rules top out around 98.6%; the rest is typos. Pakcet
      # can't match hearing pack\w*, so it goes to the LLM by design. Law
      # NN-NNNN shares its shape with other agency reports.
      it "leaves the Law Department's bill report undecided for the LLM" do
        expect(described_class.classify("Law 25-0064", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
        expect(described_class.classify("Law 25-0064 .pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
        expect(described_class.classify("Law - 25-0065.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
        expect(described_class.classify("LAW 25-0040_Small Box.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
        expect(described_class.classify("Law 25-0062.pdf", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
      end

      it "leaves an unrecoverable typo undecided rather than guessing" do
        expect(described_class.classify("Hearing Pakcet", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
      end

      it "leaves a blank or missing name undecided" do
        expect(described_class.classify("", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
        expect(described_class.classify(nil, sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
      end
    end

    context "separator and case normalization" do
      it "matches regardless of separator style or case" do
        expect(described_class.classify("public_testimony_25-0064", sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
        expect(described_class.classify("PUBLIC-TESTIMONY-25-0064", sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
        expect(described_class.classify("public.testimony.25-0064", sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
      end

      it "does not match a keyword embedded in a longer word" do
        # "Supporting Documents" states no position, so "\bsupports?\b" must
        # not match.
        expect(described_class.classify("Supporting Documents", sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
      end

      # normalize runs downcase/sub/gsub/squeeze/strip, each raising on
      # invalid UTF-8. Legistar::Client scrubs the body, so the app can't
      # reach here with bad bytes today, but the corpus rake task can.
      it "classifies a name carrying invalid UTF-8 rather than raising" do
        name = (+"Public Testimony \xC3\x28 25-0064.pdf").force_encoding(Encoding::UTF_8)

        expect(described_class.classify(name, sway_locale: "baltimore-maryland-united_states")).to eq(:testimony)
      end

      it "leaves a name that is nothing but invalid bytes undecided" do
        name = (+"\xC3\x28").force_encoding(Encoding::UTF_8)

        expect(described_class.classify(name, sway_locale: "baltimore-maryland-united_states")).to eq(:undecided)
      end
    end

    context "data-driven jurisdiction configuration" do
      it "classifies attachments when sway_locale is a SwayLocale instance with classification enabled" do
        enabled_rules = instance_double(
          SwayLocale::JurisdictionRules,
          testimony_classification_enabled?: true
        )
        enabled_locale = instance_double(
          SwayLocale,
          name: "custom-locale",
          jurisdiction_rules: enabled_rules
        )

        expect(described_class.classify("Public Testimony", sway_locale: enabled_locale)).to eq(:testimony)
        expect(described_class.classify("25-0064 Signed", sway_locale: enabled_locale)).to eq(:bill_text)
        expect(described_class.classify("Notice of Hearing", sway_locale: enabled_locale)).to eq(:procedural)
      end

      it "returns :undecided for all attachments when sway_locale is a SwayLocale instance with classification disabled" do
        disabled_rules = instance_double(
          SwayLocale::JurisdictionRules,
          testimony_classification_enabled?: false
        )
        disabled_locale = instance_double(
          SwayLocale,
          name: "disabled-locale",
          jurisdiction_rules: disabled_rules
        )

        expect(described_class.classify("Public Testimony", sway_locale: disabled_locale)).to eq(:undecided)
        expect(described_class.classify("25-0064 Signed", sway_locale: disabled_locale)).to eq(:undecided)
      end

      it "classifies attachments when sway_locale is a string slug whose registered rules have classification enabled" do
        enabled_rules = instance_double(
          SwayLocale::JurisdictionRules,
          testimony_classification_enabled?: true
        )
        allow(SwayLocale::JurisdictionRulesRegistry).to receive(:declared?).with("custom-locale").and_return(true)
        allow(SwayLocale::JurisdictionRulesRegistry).to receive(:fetch).with("custom-locale").and_return(enabled_rules)

        expect(described_class.classify("Public Testimony", sway_locale: "custom-locale")).to eq(:testimony)
        expect(described_class.classify("25-0064 Signed", sway_locale: "custom-locale")).to eq(:bill_text)
      end

      it "returns :undecided when sway_locale is a string slug whose registered rules have classification disabled" do
        disabled_rules = instance_double(
          SwayLocale::JurisdictionRules,
          testimony_classification_enabled?: false
        )
        allow(SwayLocale::JurisdictionRulesRegistry).to receive(:declared?).with("custom-locale").and_return(true)
        allow(SwayLocale::JurisdictionRulesRegistry).to receive(:fetch).with("custom-locale").and_return(disabled_rules)

        expect(described_class.classify("Public Testimony", sway_locale: "custom-locale")).to eq(:undecided)
      end

      it "returns :undecided when sway_locale string is undeclared or blank" do
        expect(described_class.classify("Public Testimony", sway_locale: "unknown-locale")).to eq(:undecided)
        expect(described_class.classify("Public Testimony", sway_locale: "")).to eq(:undecided)
        expect(described_class.classify("Public Testimony", sway_locale: nil)).to eq(:undecided)
      end

      it "gracefully returns :undecided when SwayLocale double raises Undeclared or returns nil from jurisdiction_rules" do
        failing_double = instance_double(SwayLocale)
        allow(failing_double).to receive(:jurisdiction_rules).and_raise(SwayLocale::JurisdictionRules::Undeclared.new("Not declared"))
        expect(described_class.classify("Public Testimony", sway_locale: failing_double)).to eq(:undecided)

        nil_rules_double = instance_double(SwayLocale, jurisdiction_rules: nil)
        expect(described_class.classify("Public Testimony", sway_locale: nil_rules_double)).to eq(:undecided)
      end
    end
  end

  # There is no .testimony_by_rule? block here since the method is gone —
  # nothing called it, and .classify above covers what it asserted. This
  # spec was its only reason to exist.
end
