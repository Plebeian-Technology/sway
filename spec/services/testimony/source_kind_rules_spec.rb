# frozen_string_literal: true

require "rails_helper"

RSpec.describe Testimony::SourceKindRules do
  describe ".classify" do
    it "declares the four kinds, in the order the checks run, person-speaking-for-self last" do
      expect(described_class::KINDS).to eq(
        %i[named_organization public_body person_speaking_for_org person_speaking_for_self]
      )
    end

    it "reads a city agency's own letterhead as a public body" do
      text = "On behalf of the Department of Transportation, we support Bill 25-0064."

      result = described_class.classify(text, sender_address: "planner@baltimorecity.gov")

      expect(result.kind).to eq(:public_body)
    end

    it "reads an agency letterhead in capitals above the greeting as a public body, with no 'on behalf of' phrase anywhere" do
      text = <<~TXT
        CITY OF SPRINGFIELD

        JANE DOE
        Mayor

        DEPARTMENT OF LAW
        JOHN ROE, CITY SOLICITOR
        100 MAIN STREET
        SPRINGFIELD, XX 00000

        Dear President and Council Members:

        The Law Department has reviewed Council Bill 26-0001 for form and legal sufficiency and can approve it.
      TXT

      result = described_class.classify(text, sender_address: nil)

      expect(result.kind).to eq(:public_body)
    end

    it "does NOT read a resident naming an agency mid-sentence as a public body, even in capitals" do
      text = "I called the DEPARTMENT OF PLANNING twice and nobody answered. Please pass this bill."

      result = described_class.classify(text, sender_address: "resident@example.com")

      expect(result.kind).to eq(:person_speaking_for_self)
    end

    # @lat: [[testimony-attachment-rules#Testimony attachment rules#What a sender's domain is not allowed to decide]]
    it "does NOT read an agency name in a city employee's own signature block as a letterhead — the greeting has already gone by" do
      text = <<~TXT
        Dear Council Members,

        I am writing as a resident of this block, not for my employer, to ask you to pass this bill.

        Jane Doe
        DEPARTMENT OF PUBLIC WORKS
      TXT

      result = described_class.classify(text, sender_address: "jane.doe@baltimorecity.gov")

      expect(result.kind).to eq(:person_speaking_for_self)
    end

    it "does NOT read a capitals line past the letterhead window as a letterhead when there is no greeting at all" do
      body = "I live on this block and I support the bill.\n" * 40
      text = "#{body}\nDEPARTMENT OF PLANNING\n"

      result = described_class.classify(text, sender_address: "resident@example.com")

      expect(result.kind).to eq(:person_speaking_for_self)
    end

    it "does NOT read a .gov sender domain alone as a public body, with no agency phrase in the body" do
      text = "We reviewed the bill and have no objection, speaking only for ourselves."

      result = described_class.classify(text, sender_address: "clerk@baltimorecity.gov")

      expect(result.kind).not_to eq(:public_body)
    end

    it "reads a letter written on an organization's own behalf, naming the organization as the author, as a named organization" do
      text = "On behalf of the Maryland Tenants Coalition, our organization urges you to pass this bill."

      result = described_class.classify(text, sender_address: "info@mdtenants.org")

      expect(result.kind).to eq(:named_organization)
    end

    it "reads a letter signing off with an organization name and a role at that organization as a person speaking for an organization" do
      text = <<~TEXT
        I have reviewed this bill closely and believe it will help renters.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT

      result = described_class.classify(text, sender_address: "jane@baltimorehousing.org")

      expect(result.kind).to eq(:person_speaking_for_org)
      expect(result.phrase).to include("Executive Director")
      expect(result.phrase).to include("Baltimore Housing Coalition")
      expect(result.role).to eq("Executive Director")
      expect(result.sender).to eq("jane@baltimorehousing.org")
      # @lat: [[testimony-letters#What a letter says about who is speaking]]
      expect(result.org_name).to eq("the Baltimore Housing Coalition")
    end

    it "leaves org_name nil for every kind except person_speaking_for_org" do
      public_body = described_class.classify(
        "On behalf of the Department of Transportation, we support Bill 25-0064.",
        sender_address: "planner@baltimorecity.gov"
      )
      named_organization = described_class.classify(
        "On behalf of the Maryland Tenants Coalition, our organization urges you to pass this bill.",
        sender_address: "info@mdtenants.org"
      )
      person_speaking_for_self = described_class.classify("", sender_address: nil)

      expect(public_body.org_name).to be_nil
      expect(named_organization.org_name).to be_nil
      expect(person_speaking_for_self.org_name).to be_nil
    end

    it "reads a letter with a person's name, a home address and no organization as a person speaking for themselves" do
      text = <<~TEXT
        I support this bill as a resident of this city.

        Alex Example
        100 Example Street
        Baltimore, MD 21201
      TEXT

      result = described_class.classify(text, sender_address: "alex@gmail.com")

      expect(result.kind).to eq(:person_speaking_for_self)
      expect(result.phrase).to be_nil
      expect(result.role).to be_nil
      expect(result.sender).to be_nil
    end

    it "reads a letter with nothing recognisable at all as a person speaking for themselves, not as an organization, and not as undecided" do
      result = described_class.classify("", sender_address: nil)

      expect(result.kind).to eq(:person_speaking_for_self)
    end

    it "reads nil text the same as empty text" do
      result = described_class.classify(nil, sender_address: nil)

      expect(result.kind).to eq(:person_speaking_for_self)
    end

    # The order decides: a letter that ALSO reads like one person's own
    # words (a home address, "I" throughout) still takes the org-related
    # kind the declared order gives, because person_speaking_for_self is
    # checked last, as the fallback.
    it "gives the declared-order kind, not person_speaking_for_self, when a letter reads both ways" do
      text = <<~TEXT
        I live two blocks from the proposed site and support this bill.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
        1900 Fake Street
        Baltimore, MD 21201
      TEXT

      result = described_class.classify(text, sender_address: "jane@baltimorehousing.org")

      expect(result.kind).to eq(:person_speaking_for_org)
    end

    # When not one of the three pieces of evidence can be filled — here,
    # no sender address was ever found for the letter — the kind falls
    # back to a person speaking for themselves rather than reporting
    # person_speaking_for_org with a hole in its evidence.
    it "falls back to person_speaking_for_self when the role and phrase match but no sender address was found" do
      text = <<~TEXT
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT

      result = described_class.classify(text, sender_address: nil)

      expect(result.kind).to eq(:person_speaking_for_self)
    end

    # @lat: [[testimony-attachment-rules#Every fixed phrase matches through the extracted-text helper]]
    it "reads a public body phrase broken across a line the way extracted text breaks it" do
      text = "On behalf \nof the Department of Transportation, we support Bill 25-0064."

      result = described_class.classify(text, sender_address: "planner@baltimorecity.gov")

      expect(result.kind).to eq(:public_body)
    end

    it "reads an organization's own voice when the phrase carries the double spaces extracted text carries" do
      text = "On  behalf  of the Maryland Tenants Coalition, our  organization urges you to pass this bill."

      result = described_class.classify(text, sender_address: "info@mdtenants.org")

      expect(result.kind).to eq(:named_organization)
    end

    # Written as an explicit string, not a heredoc: the trailing space before
    # the break is the whole point, and an editor or a formatter strips it
    # from a heredoc.
    it "reads a role title broken across a line as the role it is" do
      text = "I have reviewed this bill closely and believe it will help renters.\n\n" \
        "Jane Doe, Vice \nPresident of the Baltimore Housing Coalition\n"

      result = described_class.classify(text, sender_address: "jane@baltimorehousing.org")

      expect(result.kind).to eq(:person_speaking_for_org)
      expect(result.role).to eq("Vice \nPresident")
    end

    # B4, at the seam rather than at either end: the address the reader hands
    # this class is the third piece of evidence, so a domain the STORAGE
    # contract refuses used to demote a letter that plainly speaks for an
    # organization down to a person speaking for themselves — which then
    # refused that organization's own position on the bill.
    it "reads a person as speaking for an organization when the reader's address has an odd domain" do
      text = "From: jane@exa_mple.com\nJane Doe\nExecutive Director of the Baltimore Housing Coalition\n"
      sender = Testimony::SenderReader.call(text)

      result = described_class.classify(text, sender_address: sender.address)

      expect(result.kind).to eq(:person_speaking_for_org)
      expect(result.sender).to eq("jane@exa_mple.com")
    end

    # B3: "board" used to sit in AGENCY_NOUNS and public_body was checked
    # before named_organization, so an organization naming its own board of
    # directors read as a generic government agency instead of the
    # organization it actually named. Verified against the constants
    # directly before this fix landed.
    it "reads an organization naming its own board of directors as the organization, not a generic public body" do
      text = "On behalf of the Board of Directors of the Baltimore Housing Coalition, we urge you to pass this bill."

      result = described_class.classify(text, sender_address: "info@baltimorehousing.org")

      expect(result.kind).to eq(:named_organization)
    end

    it "no longer reads a generic 'office' or 'board' phrase alone as a public body" do
      text = "On behalf of the Office of the residents on our block, we support this bill."

      result = described_class.classify(text, sender_address: "resident@gmail.com")

      expect(result.kind).not_to eq(:public_body)
    end

    it "reads a public body phrase using the 'testifying for the' phrasing, not subsumed by the other public body phrase" do
      text = "Testifying for the Department of Transportation, we support Bill 25-0064."

      result = described_class.classify(text, sender_address: "planner@baltimorecity.gov")

      expect(result.kind).to eq(:public_body)
    end

    it "reads agency report phrasings ('is herein reporting on', 'prepared by the staff of', 'at its regular meeting of', 'BILL SYNOPSIS') as a public body" do
      finance = "Position: The Department of Finance is herein reporting on City Council Bill 26-0093."
      planning = "This staff report was prepared by the staff of the Department of Planning for the commission."
      meeting = "At its regular meeting of October 15, 2026, the Commission for Historical and Architectural Preservation considered City Council Bill 26-0093."
      synopsis = "BILL SYNOPSIS\nCommittee: Economic and Community Development\n Bill: 26-0093\nOffice of Equity and Civil Rights supports this bill."

      expect(described_class.classify(finance).kind).to eq(:public_body)
      expect(described_class.classify(planning).kind).to eq(:public_body)
      expect(described_class.classify(meeting).kind).to eq(:public_body)
      expect(described_class.classify(synopsis).kind).to eq(:public_body)
    end

    it "keeps a public body letter classified as :public_body even when it uses bare own-voice phrases or 'on behalf of the Mayor and City Council'" do
      letterhead_and_we_urge = "DEPARTMENT OF TRANSPORTATION\n\nDear President and Council Members:\n\nWe are writing in support of the bill and we urge a favorable report."
      on_behalf_agency_and_we_urge = "On behalf of the Department of Transportation, we urge you to pass Bill 25-0064."
      letterhead_and_mayor_council = "DEPARTMENT OF TRANSPORTATION\n\nDear President:\n\nOn behalf of the Mayor and City Council, we support this bill."
      administration_comma_council = "On behalf of the Administration, we urge the City Council to reject this amendment."

      expect(described_class.classify(letterhead_and_we_urge).kind).to eq(:public_body)
      expect(described_class.classify(on_behalf_agency_and_we_urge).kind).to eq(:public_body)
      expect(described_class.classify(letterhead_and_mayor_council).kind).to eq(:public_body)
      expect(described_class.classify("On behalf of the Administration, I ask the City Council to pass this bill.").kind).to eq(:person_speaking_for_self)
      expect(described_class.classify(administration_comma_council).kind).to eq(:named_organization)
    end

    it "stops letterhead_region at To the City Council, I am writing, or Sincerely so a city employee's signature block is not misread as a letterhead" do
      to_council = "To the City Council:\n\nI am writing as a resident of this neighborhood to support the bill.\n\nJane Doe\nDEPARTMENT OF PUBLIC WORKS"
      i_am_writing = "I am writing as a resident of Baltimore to oppose this bill.\n\nJane Doe\nDEPARTMENT OF PUBLIC WORKS"
      sincerely_signoff = "I oppose this bill because of traffic on our block.\n\nSincerely,\nJane Doe\nDEPARTMENT OF PUBLIC WORKS"

      expect(described_class.classify(to_council, sender_address: "jane.doe@baltimorecity.gov").kind).to eq(:person_speaking_for_self)
      expect(described_class.classify(i_am_writing, sender_address: "jane.doe@baltimorecity.gov").kind).to eq(:person_speaking_for_self)
      expect(described_class.classify(sincerely_signoff, sender_address: "jane.doe@baltimorecity.gov").kind).to eq(:person_speaking_for_self)
    end

    it "reads OFFICE and BOARD government letterheads above the greeting as a public body while keeping BOARD OF DIRECTORS private" do
      comptroller = "OFFICE OF THE COMPTROLLER\n\nDear President and Council Members:\n\nWe have reviewed this legislation."
      estimates = "BOARD OF ESTIMATES\n\nDear President and Council Members:\n\nThe board notes the fiscal terms."
      private_board = "BOARD OF DIRECTORS\n\nDear Council Members:\n\nOn behalf of the Baltimore Housing Coalition, we support this bill."

      expect(described_class.classify(comptroller).kind).to eq(:public_body)
      expect(described_class.classify(estimates).kind).to eq(:public_body)
      expect(described_class.classify(private_board).kind).to eq(:named_organization)
    end

    it "reads an agency study acknowledgement ('The Department of Planning wishes to thank ... study') as a public body" do
      study = "HARFORD ROAD CORRIDOR STUDY\nThe Department of Planning wishes to thank the following stakeholders for the invaluable contributions to this study."

      expect(described_class.classify(study).kind).to eq(:public_body)
    end

    it "does NOT classify a resident letter mentioning a study 'prepared by the Department' or 'bill synopsis' in prose as a public body" do
      study_ref = "I read the traffic study prepared by the Department of Transportation and disagree with its conclusions."
      synopsis_ref = "I read the bill synopsis on the city website and think the Department of Planning should hold another hearing."

      expect(described_class.classify(study_ref, sender_address: "resident@example.com").kind).to eq(:person_speaking_for_self)
      expect(described_class.classify(synopsis_ref, sender_address: "resident@example.com").kind).to eq(:person_speaking_for_self)
    end

    it "matches multi-word organization and agency phrases across converter-doubled spaces and newlines" do
      chamber_letter = "On behalf of the Downtown Chamber  of\nCommerce, we support this bill."
      agency_letter = "On  behalf\nof  the Parking Authority, we support this bill."

      expect(described_class.classify(chamber_letter, sender_address: "info@chamber.org").kind).to eq(:named_organization)
      expect(described_class.classify(agency_letter, sender_address: "info@baltimorecity.gov").kind).to eq(:public_body)
    end

    it "never returns a value outside the four declared kinds" do
      samples = [
        "",
        "On behalf of the Department of Housing, we object.",
        "On behalf of our organization, the Fells Point Coalition, we object.",
        "Jane Doe\nPresident of the Downtown Merchants Association",
        "Just a resident who cares about this issue.",
        "asdkfjaklsdjf laksjdflkasjdf"
      ]

      samples.each do |text|
        result = described_class.classify(text, sender_address: "x@example.com")
        expect(described_class::KINDS).to include(result.kind)
      end
    end
  end
end
