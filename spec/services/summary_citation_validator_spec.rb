# frozen_string_literal: true

require "rails_helper"

RSpec.describe SummaryCitationValidator do
  subject(:citation_result) { described_class.new(bill:, cited_section_keys:).call }

  let(:bill) { create(:bill) }

  context "when all cited keys are real" do
    let!(:section_a) { create(:bill_section_reference, bill:, key: "art_14__sec_301") }
    let!(:section_b) { create(:bill_section_reference, bill:, key: "art_14__sec_302") }
    let(:cited_section_keys) { ["art_14__sec_301"] }

    it "is valid with no invalid citations" do
      expect(citation_result.valid?).to be(true)
      expect(citation_result.invalid_citations).to eq([])
    end
  end

  context "when a cited key is fabricated" do
    let!(:section_a) { create(:bill_section_reference, bill:, key: "art_14__sec_301") }
    let(:cited_section_keys) { ["art_99__sec_999"] }

    it "is invalid and reports only the fabricated key" do
      expect(citation_result.valid?).to be(false)
      expect(citation_result.invalid_citations).to eq(["art_99__sec_999"])
    end
  end

  context "when the cited keys mix real and fabricated" do
    let!(:section_a) { create(:bill_section_reference, bill:, key: "art_14__sec_301") }
    let!(:section_b) { create(:bill_section_reference, bill:, key: "art_14__sec_302") }
    let(:cited_section_keys) { ["art_14__sec_301", "art_99__sec_999"] }

    it "reports only the fabricated key, not the valid one" do
      expect(citation_result.valid?).to be(false)
      expect(citation_result.invalid_citations).to eq(["art_99__sec_999"])
    end
  end

  context "when cited_section_keys is nil" do
    let!(:section_a) { create(:bill_section_reference, bill:, key: "art_14__sec_301") }
    let(:cited_section_keys) { nil }

    it "is valid with no citations to fail" do
      expect(citation_result.valid?).to be(true)
      expect(citation_result.invalid_citations).to eq([])
    end
  end

  context "when cited_section_keys is empty" do
    let!(:section_a) { create(:bill_section_reference, bill:, key: "art_14__sec_301") }
    let(:cited_section_keys) { [] }

    it "is valid with no citations to fail" do
      expect(citation_result.valid?).to be(true)
      expect(citation_result.invalid_citations).to eq([])
    end
  end

  context "when the bill has zero BillSectionReference rows" do
    let(:cited_section_keys) { ["art_1__sec_1"] }

    it "is invalid — a citation cannot be valid against zero ground truth" do
      expect(citation_result.valid?).to be(false)
      expect(citation_result.invalid_citations).to eq(["art_1__sec_1"])
    end
  end

  context "when cited_section_keys has duplicates" do
    let!(:section_a) { create(:bill_section_reference, bill:, key: "art_14__sec_301") }
    let(:cited_section_keys) { ["art_14__sec_301", "art_14__sec_301"] }

    it "does not spuriously fail on duplicate valid keys" do
      expect(citation_result.valid?).to be(true)
      expect(citation_result.invalid_citations).to eq([])
    end
  end

  describe ".allowed_news_urls" do
    it "propagates ActiveRecord::StatementInvalid when querying approved news articles fails" do
      allow(bill).to receive(:bill_news_articles).and_raise(ActiveRecord::StatementInvalid, "simulated query failure")

      expect {
        described_class.allowed_news_urls(bill)
      }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  # verdict_attrs holds the three-case rule for whether cited_section_keys
  # KEY IS PRESENT, the entry point both writers go through — they once held
  # OPPOSITE rules for the same payload.
  describe ".verdict_attrs" do
    let!(:section_a) { create(:bill_section_reference, bill:, key: "art_14__sec_301") }

    # A missing key means nothing was CITED, so nothing was CHECKED. nil is
    # the honest verdict; a clean true would claim a check that never ran —
    # the everyday case when a bill has no parsed sections.
    it "returns nil for BOTH columns when the key is absent" do
      expect(described_class.verdict_attrs(bill: bill, payload: {}))
        .to eq({citations_valid: nil, invalid_citations: nil, news_urls_valid: nil, invalid_news_urls: nil})
    end

    # ...and they go to nil even when an earlier run left a verdict on the row.
    # That old verdict describes a summary the new one has just replaced.
    it "returns nil for BOTH columns when the payload carries other keys but not this one" do
      payload = {"summary_markdown" => "## Summary", "categories" => ["Housing"]}

      expect(described_class.verdict_attrs(bill: bill, payload: payload))
        .to eq({citations_valid: nil, invalid_citations: nil, news_urls_valid: nil, invalid_news_urls: nil})
    end

    # A present but empty key is the model saying I cite nothing. That CAN be
    # checked, and nothing it cited is wrong, so the verdict is clean —
    # deliberately different from the missing-key case above.
    it "returns a CLEAN verdict when the key is present and empty" do
      expect(described_class.verdict_attrs(bill: bill, payload: {"cited_section_keys" => []}))
        .to eq({citations_valid: true, invalid_citations: [], news_urls_valid: nil, invalid_news_urls: nil})
    end

    it "validates against the bill's section references when the key is present and populated" do
      payload = {"cited_section_keys" => ["art_14__sec_301", "art_99__sec_999"]}

      expect(described_class.verdict_attrs(bill: bill, payload: payload))
        .to eq({citations_valid: false, invalid_citations: ["art_99__sec_999"], news_urls_valid: nil, invalid_news_urls: nil})
    end

    it "returns a clean verdict when every populated key is real" do
      payload = {"cited_section_keys" => ["art_14__sec_301"]}

      expect(described_class.verdict_attrs(bill: bill, payload: payload))
        .to eq({citations_valid: true, invalid_citations: [], news_urls_valid: nil, invalid_news_urls: nil})
    end

    # verdict_attrs runs the instance call exactly as written and adds
    # nothing of its own — checked here rather than taken on trust, since
    # adds nothing is what makes it safe for both writers to share.
    it "delegates to the pinned instance call and adds nothing to it" do
      payload = {"cited_section_keys" => ["art_99__sec_999"]}
      direct = described_class.new(bill: bill, cited_section_keys: payload["cited_section_keys"]).call

      expect(described_class.verdict_attrs(bill: bill, payload: payload).slice(:citations_valid, :invalid_citations))
        .to eq({citations_valid: direct.valid?, invalid_citations: direct.invalid_citations})
    end

    # What counts is whether the KEY IS THERE, not whether its value is
    # truthy. An explicit null is still present, and Array(nil) is [], so the
    # honest reading is clean, not the never-checked nil.
    it "treats an explicit null value as present, not absent" do
      expect(described_class.verdict_attrs(bill: bill, payload: {"cited_section_keys" => nil}))
        .to eq({citations_valid: true, invalid_citations: [], news_urls_valid: nil, invalid_news_urls: nil})
    end

    context "news URLs validation" do
      let(:provisioning) { create(:bill_llm_provisioning, bill: bill) }
      let(:valid_url_1) { "https://www.thebaltimorebanner.com/story-1" }
      let(:valid_url_2) { "https://baltimorefishbowl.com/story-2" }

      before do
        provisioning.update!(
          news_articles: [
            {"url" => valid_url_1, "title" => "Story 1", "cited_text" => "Snippet 1"},
            {"url" => valid_url_2, "title" => "Story 2", "cited_text" => "Snippet 2"}
          ]
        )
      end

      it "returns nil when no news claim is made" do
        payload = {"summary_markdown" => "Plain prose with no links"}
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be_nil
        expect(attrs[:invalid_news_urls]).to be_nil
      end

      it "returns clean true when cited_news_urls is an empty array" do
        payload = {"summary_markdown" => "No links", "cited_news_urls" => []}
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(true)
        expect(attrs[:invalid_news_urls]).to eq([])
      end

      it "returns clean true when cited_news_urls is nil" do
        payload = {"summary_markdown" => "No links", "cited_news_urls" => nil}
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(true)
        expect(attrs[:invalid_news_urls]).to eq([])
      end

      it "validates markdown links in summary_markdown against persisted articles" do
        payload = {
          "summary_markdown" => "Reported by [The Baltimore Banner](#{valid_url_1}).",
          "cited_news_urls" => [valid_url_1]
        }
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(true)
        expect(attrs[:invalid_news_urls]).to eq([])
      end

      it "flags unlisted markdown links in summary_markdown even if cited_news_urls is omitted" do
        unlisted = "https://unlisted-news.org/article"
        payload = {
          "summary_markdown" => "Reported by [Unlisted Outlet](#{unlisted})."
        }
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(false)
        expect(attrs[:invalid_news_urls]).to eq([unlisted])
      end

      it "flags unlisted structured URLs in cited_news_urls" do
        unlisted = "https://unlisted-news.org/article"
        payload = {
          "summary_markdown" => "Reported by [The Baltimore Banner](#{valid_url_1}).",
          "cited_news_urls" => [valid_url_1, unlisted]
        }
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(false)
        expect(attrs[:invalid_news_urls]).to eq([unlisted])
      end

      it "strips trailing punctuation from prose URLs before matching" do
        payload = {
          "summary_markdown" => "See #{valid_url_1}."
        }
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(true)
        expect(attrs[:invalid_news_urls]).to eq([])
      end

      it "fails validation when bill has no persisted news articles" do
        provisioning.update!(news_articles: [])
        payload = {
          "summary_markdown" => "Prose",
          "cited_news_urls" => [valid_url_1]
        }
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(false)
        expect(attrs[:invalid_news_urls]).to eq([valid_url_1])
      end

      it "fails validation when prose links exceed MAX_PROSE_NEWS_URLS (5)" do
        excess_urls = Array.new(6) { |i| "https://news.example.com/story-#{i}" }
        provisioning.update!(
          news_articles: excess_urls.map { |u| {"url" => u, "title" => "T"} }
        )
        prose = excess_urls.map { |u| "[Link](#{u})" }.join(" ")
        payload = {"summary_markdown" => prose}

        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(false)
        expect(attrs[:invalid_news_urls]).to eq([excess_urls.last])
      end
    end

    context "official bill link validation" do
      let(:official_url) { "https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=12345" }

      before do
        bill.update!(link: official_url)
      end

      it "accepts prose link matching bill.link as valid official citation without news articles" do
        payload = {
          "summary_markdown" => "Full text available on [Legistar](#{official_url})."
        }
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(true)
        expect(attrs[:invalid_news_urls]).to eq([])
      end

      it "accepts both official bill link and verified news links in the same summary" do
        provisioning = create(:bill_llm_provisioning, bill: bill)
        news_url = "https://www.thebaltimorebanner.com/story-1"
        provisioning.update!(
          news_articles: [{"url" => news_url, "title" => "Story 1"}]
        )

        payload = {
          "summary_markdown" => "Read [The Baltimore Banner](#{news_url}) or review [Official Bill](#{official_url}).",
          "cited_news_urls" => [news_url]
        }
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(true)
        expect(attrs[:invalid_news_urls]).to eq([])
      end

      it "does not count official link against MAX_PROSE_NEWS_URLS limit" do
        provisioning = create(:bill_llm_provisioning, bill: bill)
        news_urls = Array.new(5) { |i| "https://news.example.com/story-#{i}" }
        provisioning.update!(
          news_articles: news_urls.map { |u| {"url" => u, "title" => "Story #{u}"} }
        )
        prose_parts = news_urls.map { |u| "[News](#{u})" }
        prose_parts << "[Official Bill](#{official_url})"
        payload = {"summary_markdown" => prose_parts.join(" ")}

        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(true)
        expect(attrs[:invalid_news_urls]).to eq([])
      end

      it "rejects official bill link when a trailing slash is appended to a query parameter" do
        tampered_url = "#{official_url}/"
        payload = {
          "summary_markdown" => "Available at [Official Link](#{tampered_url})."
        }
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(false)
        expect(attrs[:invalid_news_urls]).to eq([tampered_url])
      end

      it "rejects official bill link when a trailing slash is appended to a GUID query parameter" do
        guid_url = "https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=12345&GUID=67890"
        bill.update!(link: guid_url)
        tampered_guid_url = "#{guid_url}/"
        payload = {
          "summary_markdown" => "Available at [Official Link](#{tampered_guid_url})."
        }
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(false)
        expect(attrs[:invalid_news_urls]).to eq([tampered_guid_url])
      end

      it "accepts exact supplied official link ending in a GUID query parameter" do
        guid_url = "https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=12345&GUID=67890"
        bill.update!(link: guid_url)
        payload = {
          "summary_markdown" => "Available at [Official Link](#{guid_url})."
        }
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(true)
        expect(attrs[:invalid_news_urls]).to eq([])
      end

      context "with path-only official links" do
        it "matches official link when prose URL has trailing slash on path but bill.link does not" do
          path_url = "https://www.congress.gov/bill/118th-congress/house-bill/8035/all-actions"
          bill.update!(link: path_url)
          payload = {
            "summary_markdown" => "Available at [Official Link](#{path_url}/)."
          }
          attrs = described_class.verdict_attrs(bill: bill, payload: payload)

          expect(attrs[:news_urls_valid]).to be(true)
          expect(attrs[:invalid_news_urls]).to eq([])
        end

        it "matches official link when bill.link has trailing slash on path but prose URL does not" do
          path_url = "https://www.congress.gov/bill/118th-congress/house-bill/8035/all-actions"
          bill.update!(link: "#{path_url}/")
          payload = {
            "summary_markdown" => "Available at [Official Link](#{path_url})."
          }
          attrs = described_class.verdict_attrs(bill: bill, payload: payload)

          expect(attrs[:news_urls_valid]).to be(true)
          expect(attrs[:invalid_news_urls]).to eq([])
        end
      end

      context "with generic search URLs" do
        it "filters generic search URLs returning nil from official_bill_url" do
          bill.update!(link: "https://baltimore.legistar.com/LegislationSearch.aspx")
          expect(described_class.official_bill_url(bill)).to be_nil
        end

        it "rejects generic search URLs cited in summary prose" do
          search_url = "https://baltimore.legistar.com/LegislationSearch.aspx"
          bill.update!(link: search_url)
          payload = {
            "summary_markdown" => "Available at [Search](#{search_url})."
          }
          attrs = described_class.verdict_attrs(bill: bill, payload: payload)

          expect(attrs[:news_urls_valid]).to be(false)
          expect(attrs[:invalid_news_urls]).to eq([search_url])
        end
      end

      it "rejects hallucinated or unlisted links that do not match bill.link" do
        invented_url = "https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=99999"
        payload = {
          "summary_markdown" => "See [Official Record](#{invented_url})."
        }
        attrs = described_class.verdict_attrs(bill: bill, payload: payload)

        expect(attrs[:news_urls_valid]).to be(false)
        expect(attrs[:invalid_news_urls]).to eq([invented_url])
      end

      context "with uppercase and mixed-case URL schemes" do
        it "accepts official bill link with uppercase scheme in prose markdown" do
          payload = {
            "summary_markdown" => "Available at [Official Link](#{official_url.sub("https://", "HTTPS://")})."
          }
          attrs = described_class.verdict_attrs(bill: bill, payload: payload)

          expect(attrs[:news_urls_valid]).to be(true)
          expect(attrs[:invalid_news_urls]).to eq([])
        end

        it "flags unapproved news link with uppercase scheme as invalid" do
          unapproved_url = "HTTPS://BALTIMOREBANNER.COM/TRANSIT"
          payload = {
            "summary_markdown" => "Council voted on transit [Report](#{unapproved_url})."
          }
          attrs = described_class.verdict_attrs(bill: bill, payload: payload)

          expect(attrs[:news_urls_valid]).to be(false)
          expect(attrs[:invalid_news_urls]).to eq([unapproved_url])
        end
      end
    end
  end

  describe ".extract_prose_urls" do
    it "extracts markdown links with uppercase and mixed-case schemes without mutating casing" do
      text = "Read [Report A](HTTPS://example.com/A?ID=Foo) and [Report B](Https://EXAMPLE.ORG/B)."
      expect(described_class.extract_prose_urls(text)).to eq([
        "HTTPS://example.com/A?ID=Foo",
        "Https://EXAMPLE.ORG/B"
      ])
    end

    it "extracts plain autolink URLs with uppercase and mixed-case schemes" do
      text = "Details at HTTPS://example.com/plain and HTTP://example.org/test."
      expect(described_class.extract_prose_urls(text)).to eq([
        "HTTPS://example.com/plain",
        "HTTP://example.org/test"
      ])
    end

    it "strips trailing punctuation from uppercase links" do
      text = "See [Source](HTTPS://example.com/item)!"
      expect(described_class.extract_prose_urls(text)).to eq(["HTTPS://example.com/item"])
    end

    describe "reader-visible link parsing and reference definitions" do
      it "ignores unused reference definitions" do
        text = "The council approved 50 new parks.\n\n[source]: https://thebanner.com/politics/parks"
        expect(described_class.extract_prose_urls(text)).to eq([])
      end

      it "extracts full reference links when reference is defined" do
        text = "The council approved 50 new parks. [Source][src]\n\n[src]: https://thebanner.com/politics/parks"
        expect(described_class.extract_prose_urls(text)).to eq(["https://thebanner.com/politics/parks"])
      end

      it "extracts collapsed reference links when reference is defined" do
        text = "The council approved 50 new parks. [source][]\n\n[source]: https://thebanner.com/politics/parks"
        expect(described_class.extract_prose_urls(text)).to eq(["https://thebanner.com/politics/parks"])
      end

      it "extracts shortcut reference links when reference is defined" do
        text = "The council approved 50 new parks. [source]\n\n[source]: https://thebanner.com/politics/parks"
        expect(described_class.extract_prose_urls(text)).to eq(["https://thebanner.com/politics/parks"])
      end

      it "matches reference labels case-insensitively with whitespace normalization" do
        text = "Read the [Banner Report][The  Banner].\n\n[the banner]: https://thebanner.com/article"
        expect(described_class.extract_prose_urls(text)).to eq(["https://thebanner.com/article"])
      end

      it "ignores URLs inside HTML comments" do
        text = "The council approved 50 new parks.\n\n<!-- [Source](https://thebanner.com/politics/parks) -->"
        expect(described_class.extract_prose_urls(text)).to eq([])
      end

      it "ignores URLs inside fenced code blocks" do
        text = "Code example:\n```\nhttps://example.com/ignored\n```"
        expect(described_class.extract_prose_urls(text)).to eq([])
      end

      it "ignores URLs inside inline code spans" do
        text = "Use `https://example.com/api` as the endpoint."
        expect(described_class.extract_prose_urls(text)).to eq([])
      end

      it "extracts only used definitions when mixed with unused definitions" do
        text = "Council voted [Yes][approved].\n\n[approved]: https://thebanner.com/yes\n[rejected]: https://thebanner.com/no"
        expect(described_class.extract_prose_urls(text)).to eq(["https://thebanner.com/yes"])
      end

      it "extracts autolinks enclosed in angle brackets" do
        text = "See <https://thebanner.com/direct> for details."
        expect(described_class.extract_prose_urls(text)).to eq(["https://thebanner.com/direct"])
      end

      it "ignores URLs and reference definitions inside 4-space indented code blocks" do
        text = "Code example:\n\n    https://example.com/code-block\n    [unused]: https://example.com/unused-indented"
        expect(described_class.extract_prose_urls(text)).to eq([])
      end

      it "extracts shortcut reference links followed by a colon in prose" do
        text = "According to [source]: the vote passed.\n\n[source]: https://thebanner.com/politics/parks"
        expect(described_class.extract_prose_urls(text)).to eq(["https://thebanner.com/politics/parks"])
      end

      it "ignores plain URLs in tab-indented code blocks" do
        text = "Code example:\n\n\thttps://thebanner.com/tab-code"
        expect(described_class.extract_prose_urls(text)).to eq([])
      end

      it "does not treat tab-indented lines as reference definitions" do
        text = "Council approved [source].\n\n\t[source]: https://thebanner.com/parks"
        expect(described_class.extract_prose_urls(text)).to eq([])
      end

      it "ignores URLs in double-tab and space-tab indented lines" do
        text = "Code:\n\n \thttps://thebanner.com/space-tab-code\n\t\thttps://thebanner.com/two-tabs"
        expect(described_class.extract_prose_urls(text)).to eq([])
      end

      it "applies first-definition-wins precedence for duplicate markdown reference definitions across case and whitespace" do
        text = <<~MARKDOWN
          Council voted on [Parks][src] and [Transit][THE  BANNER].

          [src]: https://thebanner.com/parks-first
          [src]: https://thebanner.com/parks-second
          [the banner]: https://thebanner.com/transit-first
          [THE  BANNER]: https://thebanner.com/transit-second
        MARKDOWN
        expect(described_class.extract_prose_urls(text)).to eq([
          "https://thebanner.com/parks-first",
          "https://thebanner.com/transit-first"
        ])
      end

      it "extracts angle-bracketed inline links and reference definitions while rejecting javascript: and mailto: schemes" do
        text = <<~MARKDOWN
          Read [Inline Angle](<https://thebanner.com/angle-inline>) and [Ref Angle][ref1] or [JS](javascript:alert(1)) or [Mail][mailref].

          [ref1]: <https://thebanner.com/angle-ref> "Title"
          [mailref]: mailto:editor@thebanner.com
        MARKDOWN
        expect(described_class.extract_prose_urls(text)).to eq([
          "https://thebanner.com/angle-inline",
          "https://thebanner.com/angle-ref"
        ])
      end

      it "extracts parenthesized markdown links and angle-bracketed URLs containing parentheses in the path" do
        text = "Details ([The Banner](https://thebanner.com/story-1)) and [Wiki](<https://example.org/bill_(2026)>)."
        expect(described_class.extract_prose_urls(text)).to eq([
          "https://thebanner.com/story-1",
          "https://example.org/bill_(2026)"
        ])
      end
    end
  end
end
