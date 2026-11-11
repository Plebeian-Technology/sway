# frozen_string_literal: true

require "rails_helper"

RSpec.describe NewsArticleTextFetchService do
  # @lat: [[news-article-evidence#Immutable article text]]
  # @lat: [[outbound-fetch-safety#Every redirect hop is checked before it is followed]]
  # @lat: [[outbound-fetch-safety#An oversized download is stopped rather than refused afterwards]]
  # @lat: [[news-source-configuration#Matching evidence]]
  let(:baltimore_locale) { create(:sway_locale, :baltimore) }
  let(:bill) { create(:bill, sway_locale: baltimore_locale) }
  let(:canonical_url) { "https://thebanner.com/politics/council-housing-bill-24-0012" }
  let(:news_article) do
    create(
      :news_article,
      canonical_url: canonical_url,
      title: "Council Passes Housing Reform",
      outlet_name: "The Baltimore Banner"
    )
  end
  let(:bill_news_article) do
    create(
      :bill_news_article,
      bill: bill,
      news_article: news_article,
      approved: false,
      match_kind: "direct"
    )
  end

  let(:valid_html_body) do
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Council Passes Housing Reform</title>
          <meta name="author" content="Jane Reporter">
          <meta property="article:published_time" content="2026-03-15T12:00:00Z">
        </head>
        <body>
          <nav>
            <a href="/">Home</a>
            <a href="/politics">Politics</a>
          </nav>
          <aside class="advertisement">
            <p>Subscribe now for only $1!</p>
          </aside>
          <main>
            <article>
              <h1>Council Passes Housing Reform</h1>
              <p>The Baltimore City Council voted overwhelmingly on Monday to advance Bill 24-0012.</p>
              <blockquote>
                "This legislation represents a vital milestone for affordable housing," stated Councilmember Harris.
              </blockquote>
              <p>The measure will allocate dedicated funding toward neighborhood revitalization projects.</p>
            </article>
          </main>
          <footer>
            <p>&copy; 2026 The Baltimore Banner. All rights reserved.</p>
          </footer>
        </body>
      </html>
    HTML
  end

  before do
    NewsArticleRobotsPolicy.reset_cache!
    stub_request(:get, %r{\Ahttps://[^/]+/robots\.txt\z})
      .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "User-agent: *\nAllow: /\n")
  end

  describe "mandatory behavioral regression (Acquire attributable article text for requested results)" do
    it "creates a retrieved NewsArticleTextVersion from a readable fixture, sets current_text_version, and computes the exact SHA-256 digest" do
      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html; charset=utf-8"},
          body: valid_html_body
        )

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      version = bill_news_article.reload.current_text_version
      expect(version).not_to be_nil
      expect(version.origin).to eq("retrieved")
      expect(version.extraction_status).to eq("extracted")
      expect(version.requested_url).to eq(canonical_url)
      expect(version.final_url).to eq(canonical_url)
      expect(version.text).to include("The Baltimore City Council voted overwhelmingly on Monday to advance Bill 24-0012.")
      expect(version.text).to include('"This legislation represents a vital milestone for affordable housing," stated Councilmember Harris.')
      expect(version.text).not_to include("Subscribe now for only $1!")
      expect(version.text).not_to include("Home")
      expect(version.digest).to eq(Digest::SHA256.hexdigest(version.text))

      expect(bill_news_article.eligible_for_synthesis?).to be false
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be true
    end

    it "leaves a link-only association and records honest failed status when upstream body is unavailable (404/500)" do
      stub_request(:get, canonical_url)
        .to_return(status: 404, body: "Not Found", headers: {"Content-Type" => "text/html"})

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
      expect(version.digest).to eq(Digest::SHA256.hexdigest(""))

      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_link?).to be true
      expect(bill_news_article.eligible_for_synthesis?).to be false
    end

    it "makes zero internal requests and halts when a redirect targets a private destination (SSRF guard)" do
      stub_request(:get, canonical_url)
        .to_return(status: 302, headers: {"Location" => "http://169.254.169.254/latest/meta-data/"})

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:any, "http://169.254.169.254/latest/meta-data/")
      expect(WebMock).not_to have_requested(:any, /169\.254\./)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
    end
  end

  describe "safety and SSRF protection" do
    it "rejects direct loopback IPv4 addresses without sending HTTP requests" do
      loopback_url = "https://127.0.0.1/article"
      news_article.update_column(:canonical_url, loopback_url)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:any, /127\.0\.0\.1/)
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
    end

    it "rejects direct private RFC 1918 addresses without sending HTTP requests" do
      private_url = "https://192.168.1.100/article"
      news_article.update_column(:canonical_url, private_url)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:any, /192\.168\./)
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
    end

    it "rejects alternative hex and mixed-hex IPv4 representations without sending HTTP requests" do
      mixed_hex_url = "https://0x7f.0.0.1/article"
      news_article.update_column(:canonical_url, mixed_hex_url)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:any, /0x7f\.0\.0\.1/)
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
    end

    it "rejects RFC 8375 home network domains (.home.arpa) without sending HTTP requests" do
      home_arpa_url = "https://node.home.arpa/article"
      news_article.update_column(:canonical_url, home_arpa_url)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:any, /node\.home\.arpa/)
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
    end

    it "rejects private domains (localhost, *.local, *.internal) without network calls" do
      internal_url = "https://service.internal/article"
      news_article.update_column(:canonical_url, internal_url)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:any, /service\.internal/)
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
    end

    it "rejects URLs with authority user credentials" do
      cred_url = "https://user:pass@thebanner.com/article"
      news_article.update_column(:canonical_url, cred_url)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:any, /thebanner\.com/)
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
    end

    it "rejects non-HTTPS schemes" do
      http_url = "http://thebanner.com/article"
      news_article.update_column(:canonical_url, http_url)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:any, /thebanner\.com/)
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
    end
  end

  describe "resource bounds and transport edge cases" do
    it "detects paywalls on 401 or 403 responses and records paywalled status honestly" do
      stub_request(:get, canonical_url)
        .to_return(status: 403, body: "Forbidden - Subscription Required", headers: {"Content-Type" => "text/html"})

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("paywalled")
      expect(version.text).to be_nil
    end

    it "records failed status on non-HTML responses (e.g. PDF or JSON)" do
      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/pdf"},
          body: "%PDF-1.4 binary data..."
        )

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
    end

    it "records failed status without crashing when receiving binary responses with invalid UTF-8 byte sequences" do
      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "image/png"},
          body: "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01".b
        )

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.not_to raise_error

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
    end

    it "records failed status when body exceeds 2 MB" do
      oversized_content = "A" * (2 * 1024 * 1024 + 100)
      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html", "Content-Length" => oversized_content.bytesize.to_s},
          body: oversized_content
        )

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
    end

    it "halts and records failed status if redirects exceed 3 hops" do
      stub_request(:get, canonical_url)
        .to_return(status: 302, headers: {"Location" => "https://thebanner.com/hop1"})
      stub_request(:get, "https://thebanner.com/hop1")
        .to_return(status: 302, headers: {"Location" => "https://thebanner.com/hop2"})
      stub_request(:get, "https://thebanner.com/hop2")
        .to_return(status: 302, headers: {"Location" => "https://thebanner.com/hop3"})
      stub_request(:get, "https://thebanner.com/hop3")
        .to_return(status: 302, headers: {"Location" => "https://thebanner.com/hop4"})

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(WebMock).not_to have_requested(:get, "https://thebanner.com/hop4")
    end
  end

  describe "locale path policy enforcement across redirects" do
    let(:sources_with_restrict) do
      [
        {
          "url" => "https://thebanner.com/politics",
          "path_policy" => "restrict"
        }
      ]
    end

    before do
      doc_reader = instance_double(SwayLocale::DocumentReader::Document, news_sources: sources_with_restrict)
      allow(SwayLocale::DocumentReader).to receive(:current_for).with(baltimore_locale).and_return(doc_reader)
    end

    it "follows redirect when destination matches restricted path prefix" do
      hop_url = "https://thebanner.com/politics/council-vote"
      stub_request(:get, canonical_url)
        .to_return(status: 302, headers: {"Location" => hop_url})
      stub_request(:get, hop_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html"},
          body: valid_html_body
        )

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("extracted")
      expect(version.final_url).to eq(hop_url)
    end

    it "halts with failed status when redirect escapes restricted path prefix" do
      escaped_url = "https://thebanner.com/sports/ravens-stadium"
      stub_request(:get, canonical_url)
        .to_return(status: 302, headers: {"Location" => escaped_url})

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(WebMock).not_to have_requested(:get, escaped_url)
    end
  end

  describe "deduplication, immutability, and administrator text protection" do
    let(:admin) { create(:user, :sway_admin) }

    it "reuses existing NewsArticleTextVersion record if fetched content digest matches" do
      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html"},
          body: valid_html_body
        )

      described_class.call(bill_news_article: bill_news_article)
      initial_version = bill_news_article.reload.current_text_version

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.not_to change(NewsArticleTextVersion, :count)

      expect(bill_news_article.reload.current_text_version_id).to eq(initial_version.id)
    end

    it "does NOT overwrite an administrator-supplied manual text version" do
      manual_version = NewsArticleTextVersion.create!(
        news_article: news_article,
        actor: admin,
        origin: "manual",
        extraction_status: "extracted",
        text: "Administrator provided verified article excerpt.",
        requested_url: canonical_url,
        final_url: canonical_url
      )
      bill_news_article.update!(current_text_version: manual_version)

      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html"},
          body: valid_html_body
        )

      described_class.call(bill_news_article: bill_news_article)

      expect(bill_news_article.reload.current_text_version_id).to eq(manual_version.id)
      expect(bill_news_article.current_text_version.origin).to eq("manual")
      expect(bill_news_article.current_text_version.text).to eq("Administrator provided verified article excerpt.")
    end

    it "isolates text version updates across bills sharing the same NewsArticle" do
      other_bill = create(:bill, sway_locale: baltimore_locale)
      other_bna = create(
        :bill_news_article,
        bill: other_bill,
        news_article: news_article,
        current_text_version: nil
      )

      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html"},
          body: valid_html_body
        )

      described_class.call(bill_news_article: bill_news_article)

      expect(bill_news_article.reload.current_text_version).not_to be_nil
      expect(other_bna.reload.current_text_version_id).to be_nil
    end
  end

  describe "metadata enrichment" do
    it "populates author_name and published_at on news_article if missing" do
      news_article.update!(author_name: nil, published_at: nil)

      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html"},
          body: valid_html_body
        )

      described_class.call(bill_news_article: bill_news_article)

      news_article.reload
      expect(news_article.author_name).to eq("Jane Reporter")
      expect(news_article.published_at).to eq(Time.utc(2026, 3, 15, 12, 0, 0))
    end
  end

  describe "(BUG) Keep inaccessible article previews out of synthesis evidence" do
    it "classifies an 80+ character preview with paywall marker as paywalled with nil text and skips metadata enrichment" do
      paywalled_preview_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Council Advances Zoning Ordinance</title>
            <meta name="author" content="Gated Reporter">
            <meta property="article:published_time" content="2026-03-20T10:00:00Z">
          </head>
          <body>
            <article>
              <h1>Council Advances Zoning Ordinance</h1>
              <p>The Baltimore City Council voted on Monday to advance a major zoning overhaul affecting commercial corridors across the city.</p>
              <div class="paywall">
                <p>Subscribe to continue reading this story. Already a subscriber? Log in.</p>
              </div>
            </article>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html; charset=utf-8"},
          body: paywalled_preview_html
        )

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("paywalled")
      expect(version.text).to be_nil
      expect(version.digest).to eq(Digest::SHA256.hexdigest(""))

      news_article.reload
      expect(news_article.author_name).to be_nil
      expect(news_article.published_at).to be_nil

      expect(bill_news_article.eligible_for_synthesis?).to be false
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
      expect(bill_news_article.eligible_for_link?).to be true
    end

    it "classifies schema.org isAccessibleForFree: 'False' as paywalled regardless of preview length" do
      jsonld_paywalled_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Port Investment Package Announced</title>
            <meta name="author" content="Gated Reporter">
            <meta property="article:published_time" content="2026-03-20T10:00:00Z">
            <script type="application/ld+json">
              {
                "@context": "https://schema.org",
                "@type": "NewsArticle",
                "headline": "Port Investment Package Announced",
                "isAccessibleForFree": "False"
              }
            </script>
          </head>
          <body>
            <article>
              <p>State and city leaders unveiled an ambitious multi-million dollar port revitalization initiative this morning at Seagirt Marine Terminal.</p>
            </article>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html; charset=utf-8"},
          body: jsonld_paywalled_html
        )

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("paywalled")
      expect(version.text).to be_nil
      expect(news_article.reload.author_name).to be_nil

      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
    end

    it "classifies schema.org isAccessibleForFree: false as paywalled regardless of preview length" do
      jsonld_boolean_paywalled_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Port Investment Package Announced</title>
            <meta name="author" content="Gated Reporter">
            <script type="application/ld+json">
              {
                "@context": "https://schema.org",
                "@type": "NewsArticle",
                "headline": "Port Investment Package Announced",
                "isAccessibleForFree": false
              }
            </script>
          </head>
          <body>
            <article>
              <p>State and city leaders unveiled an ambitious multi-million dollar port revitalization initiative this morning at Seagirt Marine Terminal.</p>
            </article>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html; charset=utf-8"},
          body: jsonld_boolean_paywalled_html
        )

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("paywalled")
      expect(version.text).to be_nil
      expect(news_article.reload.author_name).to be_nil

      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
    end

    it "classifies an HTTP 200 Cloudflare challenge page as failed with nil text and skips metadata enrichment" do
      cloudflare_challenge_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Just a moment...</title>
            <meta name="author" content="Cloudflare Security">
            <meta property="article:published_time" content="2026-03-24T12:00:00Z">
          </head>
          <body>
            <div id="challenge-running">
              <h1>Verify you are human</h1>
              <p>Please wait while we verify your browser before accessing the site. This process is automatic. Enable JavaScript and cookies to continue. Cloudflare Ray ID: 89abcdef01234567</p>
            </div>
            <form id="challenge-form" action="/challenge" method="POST"></form>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html; charset=utf-8"},
          body: cloudflare_challenge_html
        )

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
      expect(version.digest).to eq(Digest::SHA256.hexdigest(""))

      news_article.reload
      expect(news_article.author_name).to be_nil
      expect(news_article.published_at).to be_nil

      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
    end

    it "classifies a Turnstile / browser verification challenge container as failed" do
      turnstile_challenge_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Security Check | The Banner</title>
          </head>
          <body>
            <div class="cf-turnstile" data-sitekey="0x4AAAAAA"></div>
            <p>Checking your browser before accessing the article. Please verify you are human to proceed.</p>
          </body>
        </html>
      HTML

      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html; charset=utf-8"},
          body: turnstile_challenge_html
        )

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil

      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
    end

    it "classifies blocked-status (403) challenge screens as failed rather than paywalled" do
      blocked_status_challenge_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Attention Required! | Cloudflare</title>
          </head>
          <body>
            <div class="cf-browser-verification">
              <p>Checking your browser before accessing the website. Cloudflare Ray ID: 987654321.</p>
            </div>
          </body>
        </html>
      HTML

      stub_request(:get, canonical_url)
        .to_return(
          status: 403,
          headers: {"Content-Type" => "text/html; charset=utf-8"},
          body: blocked_status_challenge_html
        )

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
    end

    it "extracts clean text and enriches metadata for legitimate articles discussing CAPTCHA" do
      editorial_captcha_discussion_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>City Council Debates Bot Defenses on Public Portals</title>
            <meta name="author" content="Tech Reporter">
            <meta property="article:published_time" content="2026-03-21T09:00:00Z">
          </head>
          <body>
            <aside class="newsletter">
              <p>Subscribe to our daily newsletter for updates on council hearings.</p>
            </aside>
            <main>
              <article>
                <h1>City Council Debates Bot Defenses on Public Portals</h1>
                <p>During Thursday's technology committee hearing, council members debated the implementation of CAPTCHA and Cloudflare Turnstile verification systems on the city's housing permit website.</p>
                <p>Advocates argued that automated bots have repeatedly overwhelmed the application submission queue, locking out legitimate applicants seeking home repair grants.</p>
                <p>Councilmember Davis questioned whether privacy-preserving challenges could verify human visitors without creating accessibility hurdles for residents using screen readers.</p>
                <p>The committee resolved to pilot the verification software for a ninety-day trial period while monitoring complaint volumes from neighborhood associations.</p>
              </article>
            </main>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html; charset=utf-8"},
          body: editorial_captcha_discussion_html
        )

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("extracted")
      expect(version.text).to include("debated the implementation of CAPTCHA and Cloudflare Turnstile")
      expect(version.text).not_to include("Subscribe to our daily newsletter")

      news_article.reload
      expect(news_article.author_name).to eq("Tech Reporter")
      expect(news_article.published_at).to eq(Time.utc(2026, 3, 21, 9, 0, 0))

      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be true
    end

    it "extracts clean text for legitimate articles with ordinary subscription mention in running prose" do
      editorial_with_subscription_mention_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Transit Authority Expands Night Bus Routes</title>
            <meta name="author" content="Transit Beat">
            <meta property="article:published_time" content="2026-03-22T08:00:00Z">
          </head>
          <body>
            <main>
              <article>
                <h1>Transit Authority Expands Night Bus Routes</h1>
                <p>The regional transit administration announced expanded service hours for key bus lines connecting downtown with eastern medical centers starting next month.</p>
                <p>Community leaders praised the decision, noting that third-shift healthcare workers have faced severe transit deficits during overnight hours.</p>
                <p>Officials also noted that riders can subscribe to mobile route alerts to receive real-time schedule updates and service disruption notices.</p>
                <p>The service adjustments will take effect on the first Monday of next month with additional security patrols stationed at major transfer hubs.</p>
              </article>
            </main>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/html; charset=utf-8"},
          body: editorial_with_subscription_mention_html
        )

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("extracted")
      expect(version.text).to include("Transit Authority Expands Night Bus Routes")
      expect(news_article.reload.author_name).to eq("Transit Beat")

      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be true
    end

    it "extracts clean text when barrier phrases are inside an inline HTML <q> element" do
      html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Paywall Architecture in 2026</title>
            <meta name="author" content="Tech Reporter">
            <meta property="article:published_time" content="2026-03-28T15:00:00Z">
          </head>
          <body>
            <main>
              <article>
                <h1>Paywall Architecture in 2026</h1>
                <p>Engineering teams at national news outlets have refined meter thresholds to maximize subscription conversion.</p>
                <p>The standard warning text stating <q>you have reached your free article limit</q> is dynamically injected by reverse proxies.</p>
                <p>Consumer reactions remain divided, though subscription totals have stabilized across major metropolitan markets.</p>
              </article>
            </main>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html"}, body: html)

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("extracted")
      expect(version.text).to include("Paywall Architecture in 2026")
      expect(news_article.reload.author_name).to eq("Tech Reporter")
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be true
    end

    it "only qualifies records with approved: true, extraction_status: extracted, and non-blank text" do
      extracted_ver = create(:news_article_text_version, news_article: news_article, extraction_status: "extracted", text: "Substantive article text.")
      paywalled_ver = create(:news_article_text_version, news_article: news_article, extraction_status: "paywalled", text: nil)
      failed_ver = create(:news_article_text_version, news_article: news_article, extraction_status: "failed", text: nil)

      bill_news_article.update!(approved: false, current_text_version: extracted_ver)
      expect(bill_news_article.eligible_for_synthesis?).to be false

      bill_news_article.update!(approved: true, current_text_version: nil)
      expect(bill_news_article.eligible_for_synthesis?).to be false

      bill_news_article.update!(approved: true, current_text_version: paywalled_ver)
      expect(bill_news_article.eligible_for_synthesis?).to be false
      expect(bill_news_article.eligible_for_link?).to be true

      bill_news_article.update!(approved: true, current_text_version: failed_ver)
      expect(bill_news_article.eligible_for_synthesis?).to be false
      expect(bill_news_article.eligible_for_link?).to be true

      bill_news_article.update!(approved: true, current_text_version: extracted_ver)
      expect(bill_news_article.eligible_for_synthesis?).to be true
      expect(bill_news_article.eligible_for_link?).to be true
    end

    describe "invariants and state constraints on NewsArticleTextVersion and BillNewsArticle" do
      it "enforces strict immutability on NewsArticleTextVersion for updates and destruction" do
        version = NewsArticleTextVersion.create!(
          news_article: news_article,
          origin: "retrieved",
          extraction_status: "extracted",
          text: "Valid extracted article text exceeding minimum characters.",
          requested_url: canonical_url,
          final_url: canonical_url
        )

        expect {
          version.update!(text: "Mutated text")
        }.to raise_error(ActiveRecord::ReadOnlyRecord)

        expect {
          version.destroy!
        }.to raise_error(ActiveRecord::ReadOnlyRecord)
      end

      it "rejects invalid origins and extraction statuses" do
        expect {
          NewsArticleTextVersion.create!(
            news_article: news_article,
            origin: "invalid_origin",
            extraction_status: "extracted",
            text: "Some text"
          )
        }.to raise_error(ActiveRecord::RecordInvalid, /Origin is not included in the list/)

        expect {
          NewsArticleTextVersion.create!(
            news_article: news_article,
            origin: "retrieved",
            extraction_status: "unknown_status",
            text: "Some text"
          )
        }.to raise_error(ActiveRecord::RecordInvalid, /Extraction status is not included in the list/)
      end

      it "requires text for extracted and manual origins, but permits nil for paywalled and failed" do
        expect {
          NewsArticleTextVersion.create!(
            news_article: news_article,
            origin: "retrieved",
            extraction_status: "extracted",
            text: nil
          )
        }.to raise_error(ActiveRecord::RecordInvalid, /Text can't be blank/)

        expect {
          NewsArticleTextVersion.create!(
            news_article: news_article,
            origin: "manual",
            extraction_status: "extracted",
            text: nil
          )
        }.to raise_error(ActiveRecord::RecordInvalid, /Text can't be blank/)

        expect {
          NewsArticleTextVersion.create!(
            news_article: news_article,
            origin: "retrieved",
            extraction_status: "paywalled",
            text: nil
          )
        }.not_to raise_error

        expect {
          NewsArticleTextVersion.create!(
            news_article: news_article,
            origin: "retrieved",
            extraction_status: "failed",
            text: nil
          )
        }.not_to raise_error
      end

      it "computes digest as SHA-256 of empty string when text is nil" do
        paywalled_version = NewsArticleTextVersion.create!(
          news_article: news_article,
          origin: "retrieved",
          extraction_status: "paywalled",
          text: nil
        )
        expect(paywalled_version.digest).to eq(Digest::SHA256.hexdigest(""))

        failed_version = NewsArticleTextVersion.create!(
          news_article: news_article,
          origin: "retrieved",
          extraction_status: "failed",
          text: nil
        )
        expect(failed_version.digest).to eq(Digest::SHA256.hexdigest(""))
      end

      it "validates usable_text? predicate semantics strictly" do
        extracted_valid = NewsArticleTextVersion.new(extraction_status: "extracted", text: "Valid content")
        extracted_blank = NewsArticleTextVersion.new(extraction_status: "extracted", text: "   ")
        extracted_nil = NewsArticleTextVersion.new(extraction_status: "extracted", text: nil)
        paywalled = NewsArticleTextVersion.new(extraction_status: "paywalled", text: nil)
        failed = NewsArticleTextVersion.new(extraction_status: "failed", text: nil)

        expect(extracted_valid.usable_text?).to be true
        expect(extracted_blank.usable_text?).to be false
        expect(extracted_nil.usable_text?).to be false
        expect(paywalled.usable_text?).to be false
        expect(failed.usable_text?).to be false
      end

      it "maintains SQL scope parity with Ruby predicate across status and whitespace variants" do
        extracted_valid = create(:news_article_text_version, news_article: news_article, extraction_status: "extracted", text: "Substantive article text.")
        paywalled = create(:news_article_text_version, news_article: news_article, extraction_status: "paywalled", text: nil)
        failed = create(:news_article_text_version, news_article: news_article, extraction_status: "failed", text: nil)

        bill_news_article.update!(approved: false, current_text_version: extracted_valid)
        expect(bill_news_article.eligible_for_synthesis?).to be false
        expect(BillNewsArticle.eligible_for_synthesis).not_to include(bill_news_article)

        bill_news_article.update!(approved: true, current_text_version: paywalled)
        expect(bill_news_article.eligible_for_synthesis?).to be false
        expect(BillNewsArticle.eligible_for_synthesis).not_to include(bill_news_article)
        expect(bill_news_article.eligible_for_link?).to be true

        bill_news_article.update!(approved: true, current_text_version: failed)
        expect(bill_news_article.eligible_for_synthesis?).to be false
        expect(BillNewsArticle.eligible_for_synthesis).not_to include(bill_news_article)
        expect(bill_news_article.eligible_for_link?).to be true

        bill_news_article.update!(approved: true, current_text_version: nil)
        expect(bill_news_article.eligible_for_synthesis?).to be false
        expect(BillNewsArticle.eligible_for_synthesis).not_to include(bill_news_article)
        expect(bill_news_article.eligible_for_link?).to be true

        bill_news_article.update!(approved: true, current_text_version: extracted_valid)
        expect(bill_news_article.eligible_for_synthesis?).to be true
        expect(BillNewsArticle.eligible_for_synthesis).to include(bill_news_article)
        expect(bill_news_article.eligible_for_link?).to be true

        bill_news_article.update!(approved: false, current_text_version: nil)
        expect(bill_news_article.eligible_for_synthesis?).to be false
        expect(BillNewsArticle.eligible_for_synthesis).not_to include(bill_news_article)
        expect(bill_news_article.eligible_for_link?).to be false
      end

      it "rejects cross-article current_text_version assignment" do
        other_article = create(:news_article, canonical_url: "https://example.com/other")
        foreign_version = create(:news_article_text_version, news_article: other_article, extraction_status: "extracted", text: "Foreign text.")

        bill_news_article.current_text_version = foreign_version
        expect(bill_news_article).not_to be_valid
        expect(bill_news_article.errors[:current_text_version]).to include("must belong to the associated news article")
      end
    end

    describe "metadata enrichment guard verification under error, paywall, challenge, and valid HTML" do
      before do
        news_article.update!(author_name: nil, published_at: nil)
      end

      it "does not enrich metadata when response is HTTP 404 or HTTP 500" do
        html_with_metadata = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <meta name="author" content="Error Reporter">
              <meta property="article:published_time" content="2026-03-24T10:00:00Z">
            </head>
            <body><h1>404 Not Found</h1></body>
          </html>
        HTML

        stub_request(:get, canonical_url)
          .to_return(status: 404, headers: {"Content-Type" => "text/html"}, body: html_with_metadata)

        described_class.call(bill_news_article: bill_news_article)

        news_article.reload
        expect(news_article.author_name).to be_nil
        expect(news_article.published_at).to be_nil
        expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
      end

      it "does not enrich metadata when text is too short (< 50 chars) despite lack of access barriers" do
        short_html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Brief Snippet</title>
              <meta name="author" content="Short Reporter">
              <meta property="article:published_time" content="2026-03-24T10:00:00Z">
            </head>
            <body>
              <article>
                <p>Too short.</p>
              </article>
            </body>
          </html>
        HTML

        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html"}, body: short_html)

        described_class.call(bill_news_article: bill_news_article)

        news_article.reload
        expect(news_article.author_name).to be_nil
        expect(news_article.published_at).to be_nil
        expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
      end

      it "does not enrich metadata when paywall indicator is detected in HTML" do
        paywall_html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Subscriber Exclusive Investigation</title>
              <meta name="author" content="Paywall Reporter">
              <meta property="article:published_time" content="2026-03-24T10:00:00Z">
            </head>
            <body>
              <article>
                <p>An extensive ninety-character preview introducing an investigative report into city budgeting.</p>
                <div class="locked-body">
                  <p>Unlock this story with a subscription.</p>
                </div>
              </article>
            </body>
          </html>
        HTML

        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html"}, body: paywall_html)

        described_class.call(bill_news_article: bill_news_article)

        news_article.reload
        expect(news_article.author_name).to be_nil
        expect(news_article.published_at).to be_nil
        expect(bill_news_article.reload.current_text_version.extraction_status).to eq("paywalled")
      end

      it "does not enrich metadata when challenge indicator is detected in HTML" do
        challenge_html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Security Check</title>
              <meta name="author" content="Security Bot">
              <meta property="article:published_time" content="2026-03-24T10:00:00Z">
            </head>
            <body>
              <div id="captcha-container">
                <p>Please complete the security check to continue accessing the news website.</p>
              </div>
            </body>
          </html>
        HTML

        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html"}, body: challenge_html)

        described_class.call(bill_news_article: bill_news_article)

        news_article.reload
        expect(news_article.author_name).to be_nil
        expect(news_article.published_at).to be_nil
        expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
      end

      it "enriches metadata only when article is successfully extracted and preserves existing metadata" do
        news_article.update!(author_name: "Pre-existing Author", published_at: nil)

        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html"}, body: valid_html_body)

        described_class.call(bill_news_article: bill_news_article)

        news_article.reload
        expect(news_article.author_name).to eq("Pre-existing Author")
        expect(news_article.published_at).to eq(Time.utc(2026, 3, 15, 12, 0, 0))
        expect(bill_news_article.reload.current_text_version.extraction_status).to eq("extracted")
      end
    end

    describe "HTTP status code matrix (401, 403, 429, 451, 503)" do
      let(:challenge_screen_html) do
        <<~HTML
          <!DOCTYPE html>
          <html>
            <head><title>Attention Required! | Cloudflare</title></head>
            <body>
              <div id="cf-wrapper">
                <p>Please wait while your request is being verified.</p>
              </div>
            </body>
          </html>
        HTML
      end

      let(:paywall_screen_html) do
        <<~HTML
          <!DOCTYPE html>
          <html>
            <head><title>Subscription Required</title></head>
            <body>
              <div class="paywall">
                <p>Subscription required to view this story.</p>
              </div>
            </body>
          </html>
        HTML
      end

      it "classifies blocked statuses (401, 403, 429, 451, 503) with challenge HTML as failed" do
        [401, 403, 429, 451, 503].each do |status_code|
          stub_request(:get, canonical_url)
            .to_return(status: status_code, headers: {"Content-Type" => "text/html"}, body: challenge_screen_html)

          described_class.call(bill_news_article: bill_news_article)
          expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
        end
      end

      it "classifies 401, 403, 451 with paywall HTML as paywalled" do
        [401, 403, 451].each do |status_code|
          stub_request(:get, canonical_url)
            .to_return(status: status_code, headers: {"Content-Type" => "text/html"}, body: paywall_screen_html)

          described_class.call(bill_news_article: bill_news_article)
          expect(bill_news_article.reload.current_text_version.extraction_status).to eq("paywalled")
        end
      end

      it "classifies 429 and 503 with paywall HTML as failed" do
        [429, 503].each do |status_code|
          stub_request(:get, canonical_url)
            .to_return(status: status_code, headers: {"Content-Type" => "text/html"}, body: paywall_screen_html)

          described_class.call(bill_news_article: bill_news_article)
          expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
        end
      end
    end

    describe "adversarial challenge screens and paywall evasion edge cases" do
      it "detects iframe-based challenge widgets (Cloudflare, reCAPTCHA, hCaptcha, PerimeterX)" do
        iframe_payloads = [
          "<iframe src=\"https://challenges.cloudflare.com/cdn-cgi/challenge-platform/h/b/turnstile\"></iframe>",
          "<iframe src=\"https://www.google.com/recaptcha/api2/anchor?k=123\"></iframe>",
          "<iframe src=\"https://newassets.hcaptcha.com/captcha/v1/anchor.html\"></iframe>",
          "<iframe src=\"https://captcha.perimeterx.net/px/123/captcha.js\"></iframe>"
        ]

        iframe_payloads.each do |iframe_tag|
          html = <<~HTML
            <!DOCTYPE html>
            <html>
              <head><title>Article Heading</title></head>
              <body>
                <article>
                  <p>This is a sixty-character introductory paragraph that appears before an access barrier.</p>
                  <div>#{iframe_tag}</div>
                </article>
              </body>
            </html>
          HTML

          stub_request(:get, canonical_url)
            .to_return(status: 200, headers: {"Content-Type" => "text/html"}, body: html)

          described_class.call(bill_news_article: bill_news_article)
          expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
        end
      end

      it "detects data-attribute and metered paywall gates" do
        paywall_attributes = [
          "<div data-paywall=\"true\"><p>Subscribers only</p></div>",
          "<div data-locked=\"true\"><p>Subscribers only</p></div>",
          "<div data-subscriber-restricted=\"true\"><p>Subscribers only</p></div>",
          "<div class=\"metered-barrier\"><p>Monthly limit reached</p></div>",
          "<div class=\"metered-wall\"><p>Monthly limit reached</p></div>"
        ]

        paywall_attributes.each do |gate_tag|
          html = <<~HTML
            <!DOCTYPE html>
            <html>
              <head><title>Article Heading</title></head>
              <body>
                <article>
                  <p>This is a seventy-character introductory paragraph describing municipal legislation in Baltimore.</p>
                  <div>#{gate_tag}</div>
                </article>
              </body>
            </html>
          HTML

          stub_request(:get, canonical_url)
            .to_return(status: 200, headers: {"Content-Type" => "text/html"}, body: html)

          described_class.call(bill_news_article: bill_news_article)
          expect(bill_news_article.reload.current_text_version.extraction_status).to eq("paywalled")
        end
      end

      it "detects 302 redirect leading to a Cloudflare challenge page as failed" do
        hop_url = "https://thebanner.com/cdn-cgi/challenge"
        stub_request(:get, canonical_url)
          .to_return(status: 302, headers: {"Location" => hop_url})
        stub_request(:get, hop_url)
          .to_return(
            status: 403,
            headers: {"Content-Type" => "text/html"},
            body: <<~HTML
              <html><head><title>Just a moment...</title></head><body><div id="cf-challenge-running">Checking browser</div></body></html>
            HTML
          )

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.final_url).to eq(hop_url)
        expect(version.text).to be_nil
      end
    end
  end

  describe "(BUG) Honor every configured source path during article retrieval" do
    let(:doc_reader) { instance_double(SwayLocale::DocumentReader::Document) }

    before do
      allow(SwayLocale::DocumentReader).to receive(:current_for).with(baltimore_locale).and_return(doc_reader)
    end

    describe "multi-path matching on same host with restricted paths (order independence)" do
      let(:sources_politics_first) do
        [
          {"url" => "https://thebanner.com/politics", "path_policy" => "restrict"},
          {"url" => "https://thebanner.com/local", "path_policy" => "restrict"}
        ]
      end

      let(:sources_local_first) do
        [
          {"url" => "https://thebanner.com/local", "path_policy" => "restrict"},
          {"url" => "https://thebanner.com/politics", "path_policy" => "restrict"}
        ]
      end

      it "permits descendant of second path when /politics is configured first" do
        allow(doc_reader).to receive(:news_sources).and_return(sources_politics_first)
        local_url = "https://thebanner.com/local/community-zoning-hearing"
        news_article.update_column(:canonical_url, local_url)

        stub_request(:get, local_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
        expect(version.text).to include("The Baltimore City Council voted overwhelmingly")
        expect(WebMock).to have_requested(:get, local_url).once
      end

      it "permits descendant of second path when /local is configured first" do
        allow(doc_reader).to receive(:news_sources).and_return(sources_local_first)
        politics_url = "https://thebanner.com/politics/council-housing-bill-24-0012"
        news_article.update_column(:canonical_url, politics_url)

        stub_request(:get, politics_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
        expect(version.text).to include("The Baltimore City Council voted overwhelmingly")
        expect(WebMock).to have_requested(:get, politics_url).once
      end

      it "permits exact path match for either configured restricted source" do
        allow(doc_reader).to receive(:news_sources).and_return(sources_politics_first)

        ["https://thebanner.com/politics", "https://thebanner.com/local"].each do |url|
          article = create(:news_article, canonical_url: url, title: "Article for #{url}")
          association = create(:bill_news_article, bill: bill, news_article: article)
          stub_request(:get, url)
            .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

          described_class.call(bill_news_article: association)

          version = association.reload.current_text_version
          expect(version.extraction_status).to eq("extracted")
          expect(version.final_url).to eq(url)
        end
      end

      it "rejects outside path on same host without making network requests" do
        allow(doc_reader).to receive(:news_sources).and_return(sources_politics_first)
        sports_url = "https://thebanner.com/sports/ravens-stadium-lease"
        news_article.update_column(:canonical_url, sports_url)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.text).to be_nil
        expect(WebMock).not_to have_requested(:get, sports_url)
      end

      it "rejects sibling prefix collision that is not a true subpath directory" do
        allow(doc_reader).to receive(:news_sources).and_return(sources_politics_first)
        collision_url = "https://thebanner.com/politics-and-policy/story"
        news_article.update_column(:canonical_url, collision_url)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.text).to be_nil
        expect(WebMock).not_to have_requested(:get, collision_url)
      end
    end

    describe "mixed path policies on same host (restrict and search_hint)" do
      let(:restrict_then_search_hint) do
        [
          {"url" => "https://thebanner.com/politics", "path_policy" => "restrict"},
          {"url" => "https://thebanner.com/", "path_policy" => "search_hint"}
        ]
      end

      let(:search_hint_then_restrict) do
        [
          {"url" => "https://thebanner.com/", "path_policy" => "search_hint"},
          {"url" => "https://thebanner.com/politics", "path_policy" => "restrict"}
        ]
      end

      it "permits arbitrary paths when search_hint is present alongside restrict regardless of order" do
        [restrict_then_search_hint, search_hint_then_restrict].each_with_index do |sources, idx|
          allow(doc_reader).to receive(:news_sources).and_return(sources)
          opinion_url = "https://thebanner.com/opinion/editorial-board-housing-#{idx}"
          article = create(:news_article, canonical_url: opinion_url, title: "Editorial #{idx}")
          association = create(:bill_news_article, bill: bill, news_article: article)

          stub_request(:get, opinion_url)
            .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

          described_class.call(bill_news_article: association)

          version = association.reload.current_text_version
          expect(version.extraction_status).to eq("extracted")
          expect(version.final_url).to eq(opinion_url)
        end
      end
    end

    describe "multiple configured hosts and host isolation" do
      let(:multi_host_sources) do
        [
          {"url" => "https://thebanner.com/politics", "path_policy" => "restrict"},
          {"url" => "https://baltimoresun.com/maryland", "path_policy" => "restrict"},
          {"url" => "https://wypr.org/", "path_policy" => "search_hint"}
        ]
      end

      before do
        allow(doc_reader).to receive(:news_sources).and_return(multi_host_sources)
      end

      it "permits valid paths matching each respective host" do
        [
          "https://thebanner.com/politics/council-update",
          "https://baltimoresun.com/maryland/education-budget",
          "https://wypr.org/podcast/local-politics-hour"
        ].each do |url|
          article = create(:news_article, canonical_url: url, title: "Article for #{url}")
          association = create(:bill_news_article, bill: bill, news_article: article)
          stub_request(:get, url)
            .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

          described_class.call(bill_news_article: association)

          version = association.reload.current_text_version
          expect(version.extraction_status).to eq("extracted")
          expect(version.final_url).to eq(url)
        end
      end

      it "does not allow a path configured on host B to authorize an unconfigured path on host A" do
        cross_url = "https://thebanner.com/maryland/cross-pollution-test"
        news_article.update_column(:canonical_url, cross_url)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(WebMock).not_to have_requested(:get, cross_url)
      end

      it "normalizes www. prefix between candidate URL and configured source" do
        www_url = "https://www.thebanner.com/politics/council-update"
        news_article.update_column(:canonical_url, www_url)

        stub_request(:get, www_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
        expect(WebMock).to have_requested(:get, www_url).once
      end

      it "rejects unconfigured domains entirely without sending network requests" do
        foreign_url = "https://washingtonpost.com/politics/federal-grants"
        news_article.update_column(:canonical_url, foreign_url)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(WebMock).not_to have_requested(:get, foreign_url)
      end
    end

    describe "trailing slash variations and subpath nesting" do
      it "handles trailing slash on source matching URL without trailing slash" do
        sources = [{"url" => "https://thebanner.com/politics/", "path_policy" => "restrict"}]
        allow(doc_reader).to receive(:news_sources).and_return(sources)

        url_no_slash = "https://thebanner.com/politics"
        news_article.update_column(:canonical_url, url_no_slash)

        stub_request(:get, url_no_slash)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
      end

      it "handles source without trailing slash matching nested descendant paths" do
        sources = [{"url" => "https://thebanner.com/politics", "path_policy" => "restrict"}]
        allow(doc_reader).to receive(:news_sources).and_return(sources)

        nested_url = "https://thebanner.com/politics/2026/09/24/council-passes-resolution"
        news_article.update_column(:canonical_url, nested_url)

        stub_request(:get, nested_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
      end
    end

    describe "fail-closed semantics on absent, empty, or unreadable source configuration" do
      it "fails closed and makes zero requests when news_sources is empty" do
        allow(doc_reader).to receive(:news_sources).and_return([])

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.text).to be_nil
        expect(WebMock).not_to have_requested(:get, canonical_url)
      end

      it "fails closed and makes zero requests when news_sources is nil" do
        allow(doc_reader).to receive(:news_sources).and_return(nil)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.text).to be_nil
        expect(WebMock).not_to have_requested(:get, canonical_url)
      end

      it "fails closed when DocumentReader raises an error" do
        allow(SwayLocale::DocumentReader).to receive(:current_for).with(baltimore_locale).and_raise(StandardError, "Corrupt YAML")

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.text).to be_nil
        expect(WebMock).not_to have_requested(:get, canonical_url)
      end

      it "fails closed when DocumentReader returns an object lacking news_sources" do
        allow(SwayLocale::DocumentReader).to receive(:current_for).with(baltimore_locale).and_return(Object.new)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.text).to be_nil
        expect(WebMock).not_to have_requested(:get, canonical_url)
      end

      it "fails closed when bill_news_article has nil sway_locale" do
        allow(bill_news_article).to receive(:sway_locale).and_return(nil)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.text).to be_nil
        expect(WebMock).not_to have_requested(:get, canonical_url)
      end
    end

    describe "HTTP 301 and 302 redirects with multi-path and fail-closed policies" do
      let(:multi_sources) do
        [
          {"url" => "https://thebanner.com/politics", "path_policy" => "restrict"},
          {"url" => "https://thebanner.com/local", "path_policy" => "restrict"},
          {"url" => "https://baltimoresun.com/city-hall", "path_policy" => "restrict"}
        ]
      end

      before do
        allow(doc_reader).to receive(:news_sources).and_return(multi_sources)
      end

      it "follows 301 redirect from first configured path to second configured path on same host" do
        start_url = "https://thebanner.com/politics/old-slug"
        target_url = "https://thebanner.com/local/new-slug"
        news_article.update_column(:canonical_url, start_url)

        stub_request(:get, start_url).to_return(status: 301, headers: {"Location" => target_url})
        stub_request(:get, target_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
        expect(version.final_url).to eq(target_url)
      end

      it "follows 302 redirect from second configured path to first configured path on same host" do
        start_url = "https://thebanner.com/local/old-slug"
        target_url = "https://thebanner.com/politics/new-slug"
        news_article.update_column(:canonical_url, start_url)

        stub_request(:get, start_url).to_return(status: 302, headers: {"Location" => target_url})
        stub_request(:get, target_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
        expect(version.final_url).to eq(target_url)
      end

      it "follows redirect across different permitted hosts when both paths match their host policy" do
        start_url = "https://thebanner.com/politics/old-slug"
        target_url = "https://baltimoresun.com/city-hall/new-slug"
        news_article.update_column(:canonical_url, start_url)

        stub_request(:get, start_url).to_return(status: 302, headers: {"Location" => target_url})
        stub_request(:get, target_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
        expect(version.final_url).to eq(target_url)
      end

      it "halts redirect when destination host is configured but path violates host restriction" do
        start_url = "https://thebanner.com/politics/old-slug"
        unpermitted_sun_url = "https://baltimoresun.com/sports/orioles"
        news_article.update_column(:canonical_url, start_url)

        stub_request(:get, start_url).to_return(status: 302, headers: {"Location" => unpermitted_sun_url})

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(WebMock).not_to have_requested(:get, unpermitted_sun_url)
      end

      it "halts redirect when destination targets an unconfigured domain" do
        start_url = "https://thebanner.com/politics/old-slug"
        unconfigured_url = "https://untrusted-outbound.com/article"
        news_article.update_column(:canonical_url, start_url)

        stub_request(:get, start_url).to_return(status: 302, headers: {"Location" => unconfigured_url})

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(WebMock).not_to have_requested(:get, unconfigured_url)
      end

      it "rejects uppercase path in target URL because URL paths are case-sensitive" do
        upper_path_url = "https://thebanner.com/POLITICS/council-vote"
        news_article.update_column(:canonical_url, upper_path_url)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(WebMock).not_to have_requested(:get, upper_path_url)
      end

      it "rejects percent-encoded slash in root resource name (/politics%2Flocal)" do
        encoded_slash_url = "https://thebanner.com/politics%2Flocal"
        news_article.update_column(:canonical_url, encoded_slash_url)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(WebMock).not_to have_requested(:get, encoded_slash_url)
      end

      it "resolves relative redirect with dot segments and rejects when escaping restricted boundary" do
        start_url = "https://thebanner.com/politics/section/article"
        escaped_target = "https://thebanner.com/sports/article"
        news_article.update_column(:canonical_url, start_url)

        stub_request(:get, start_url).to_return(status: 301, headers: {"Location" => "../../sports/article"})

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(WebMock).to have_requested(:get, start_url).once
        expect(WebMock).not_to have_requested(:get, escaped_target)
      end

      it "supports symbol-keyed source hashes in news_sources" do
        symbol_doc_reader = instance_double(
          SwayLocale::DocumentReader::Document,
          news_sources: [
            {url: "https://thebanner.com/politics", path_policy: "restrict"},
            {url: "https://thebanner.com/local", path_policy: "restrict"}
          ]
        )
        allow(SwayLocale::DocumentReader).to receive(:current_for).with(baltimore_locale).and_return(symbol_doc_reader)

        target_url = "https://thebanner.com/local/report"
        news_article.update_column(:canonical_url, target_url)
        stub_request(:get, target_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
      end
    end
  end

  describe "(BUG) Respect robots.txt before retrieving article text" do
    before do
      NewsArticleRobotsPolicy.reset_cache!
    end

    it "halts retrieval with zero article requests when robots.txt disallows SwayCivic explicitly" do
      robots_txt = <<~ROBOTS
        User-agent: SwayCivic
        Disallow: /politics/
      ROBOTS

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_disallowed,
          url: canonical_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(WebMock).to have_requested(:get, "https://thebanner.com/robots.txt").once

      version = bill_news_article.reload.current_text_version
      expect(version.origin).to eq("retrieved")
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
      expect(version.digest).to eq(Digest::SHA256.hexdigest(""))

      expect(bill_news_article.eligible_for_synthesis?).to be false
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
      expect(bill_news_article.eligible_for_link?).to be true
    end

    it "halts retrieval when robots.txt disallows wildcard * in absence of SwayCivic group" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /politics/
      ROBOTS

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
    end

    it "retrieves article when SwayCivic explicitly allows path even if wildcard * disallows it" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /politics/

        User-agent: SwayCivic
        Allow: /politics/
      ROBOTS

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).to have_requested(:get, canonical_url).once
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("extracted")
      expect(version.text).to include("The Baltimore City Council voted overwhelmingly")
    end

    it "retrieves article normally when robots.txt is 404 Not Found" do
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 404, body: "Not Found")

      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).to have_requested(:get, canonical_url).once
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("extracted")
    end

    it "fails closed with zero article requests when robots.txt returns HTTP 500" do
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 500, body: "Internal Server Error")

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
    end

    it "fails closed with zero article requests when robots.txt connection times out" do
      stub_request(:get, "https://thebanner.com/robots.txt").to_timeout

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
    end

    it "fails closed with zero article requests when robots.txt returns challenge HTML" do
      challenge_html = <<~HTML
        <html><head><title>Attention Required! | Cloudflare</title></head><body><div id="cf-challenge-running"></div></body></html>
      HTML
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 403, headers: {"Content-Type" => "text/html"}, body: challenge_html)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
    end

    it "fails closed with zero article requests when robots.txt returns HTML subscription page on HTTP 200" do
      html_subscription = <<~HTML
        <!DOCTYPE html>
        <html>
          <head><title>Account</title></head>
          <body>
            <h1>Subscribe to continue</h1>
            <p>Please purchase a digital subscription to read further.</p>
          </body>
        </html>
      HTML

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html_subscription)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_inaccessible,
          url: canonical_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(WebMock).to have_requested(:get, "https://thebanner.com/robots.txt").once

      version = bill_news_article.reload.current_text_version
      expect(version.origin).to eq("retrieved")
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
      expect(version.digest).to eq(Digest::SHA256.hexdigest(""))

      expect(bill_news_article.eligible_for_synthesis?).to be false
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
      expect(bill_news_article.eligible_for_link?).to be true
    end

    it "fails closed with zero article requests when robots.txt returns HTTP 404 with CAPTCHA challenge markup" do
      captcha_html = '<html><title>Human Verification</title><body><div class="h-captcha" data-sitekey="test"></div></body></html>'
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 404, headers: {"Content-Type" => "text/html"}, body: captcha_html)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_challenged,
          url: canonical_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(WebMock).to have_requested(:get, "https://thebanner.com/robots.txt").once

      version = bill_news_article.reload.current_text_version
      expect(version.origin).to eq("retrieved")
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
      expect(version.digest).to eq(Digest::SHA256.hexdigest(""))

      expect(bill_news_article.eligible_for_synthesis?).to be false
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
      expect(bill_news_article.eligible_for_link?).to be true
    end

    it "fails closed with zero article requests when robots.txt returns HTTP 410 with CAPTCHA challenge markup" do
      captcha_html = '<!DOCTYPE html><html><head><title>Just a moment...</title></head><body><div id="cf-challenge-running"></div></body></html>'
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 410, headers: {"Content-Type" => "text/html"}, body: captcha_html)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
    end

    it "fails closed with zero article requests when robots.txt returns HTTP 404 with login barrier markup" do
      login_html = '<div><h1>Sign in</h1><form action="/login"><input type="password"><button>Sign in</button></form></div>'
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 404, headers: {"Content-Type" => "text/html"}, body: login_html)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_inaccessible,
          url: canonical_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
    end

    it "fails closed with zero article requests when robots.txt returns HTTP 410 with login barrier markup" do
      login_html = '<form action="/auth/login" method="post"><input type="password" name="password"><input type="submit" value="Log In"></form>'
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 410, headers: {"Content-Type" => "text/html"}, body: login_html)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
    end

    it "fails closed with zero article requests when robots.txt returns HTTP 404 with paywall barrier markup" do
      paywall_html = '<div class="paywall"><h2>Subscribe to continue</h2><p>This content is for subscribers only.</p></div>'
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 404, headers: {"Content-Type" => "text/html"}, body: paywall_html)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
    end

    it "fails closed with zero article requests when robots.txt returns HTTP 200 with HTML login fragment served as text/plain" do
      login_fragment = '<div><h1>Sign in</h1><form action="/login"><input type="password"><button>Sign in</button></form></div>'
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: login_fragment)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_inaccessible,
          url: canonical_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(WebMock).to have_requested(:get, "https://thebanner.com/robots.txt").once

      version = bill_news_article.reload.current_text_version
      expect(version.origin).to eq("retrieved")
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
      expect(version.digest).to eq(Digest::SHA256.hexdigest(""))

      expect(bill_news_article.eligible_for_synthesis?).to be false
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
      expect(bill_news_article.eligible_for_link?).to be true
    end

    it "fails closed with zero article requests when robots.txt returns HTTP 200 with HTML login fragment when Content-Type is omitted" do
      login_fragment = '<div><h1>Sign in</h1><form action="/login"><input type="password"><button>Sign in</button></form></div>'
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, body: login_fragment)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).not_to have_requested(:get, canonical_url)
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
    end

    it "retrieves article normally when robots.txt returns genuine HTTP 404 with standard HTML not-found page" do
      standard_404_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head><title>404 Not Found</title></head>
          <body>
            <h1>404 Not Found</h1>
            <p>The requested URL /robots.txt was not found on this server.</p>
          </body>
        </html>
      HTML
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 404, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: standard_404_html)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).to have_requested(:get, canonical_url).once
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("extracted")
    end

    it "retrieves article normally when robots.txt returns genuine HTTP 410 with standard HTML gone page" do
      standard_410_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head><title>410 Gone</title></head>
          <body>
            <h1>Resource Gone</h1>
            <p>The robots.txt file has been permanently removed.</p>
          </body>
        </html>
      HTML
      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 410, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: standard_410_html)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).to have_requested(:get, canonical_url).once
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("extracted")
    end

    describe "redirect policy enforcement" do
      it "halts redirect and makes zero requests to destination when destination is disallowed by robots.txt" do
        initial_url = "https://thebanner.com/politics/initial-slug"
        redirected_url = "https://thebanner.com/internal-archive/final-slug"
        news_article.update_column(:canonical_url, initial_url)

        doc_reader = instance_double(
          SwayLocale::DocumentReader::Document,
          news_sources: [
            {"url" => "https://thebanner.com/politics", "path_policy" => "search_hint"},
            {"url" => "https://thebanner.com/internal-archive", "path_policy" => "search_hint"}
          ]
        )
        allow(SwayLocale::DocumentReader).to receive(:current_for).with(baltimore_locale).and_return(doc_reader)

        robots_txt = <<~ROBOTS
          User-agent: *
          Allow: /politics/
          Disallow: /internal-archive/
        ROBOTS

        stub_request(:get, "https://thebanner.com/robots.txt")
          .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

        stub_request(:get, initial_url)
          .to_return(status: 302, headers: {"Location" => redirected_url})

        described_class.call(bill_news_article: bill_news_article)

        expect(WebMock).to have_requested(:get, initial_url).once
        expect(WebMock).not_to have_requested(:get, redirected_url)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.text).to be_nil
      end

      it "checks destination host robots.txt on cross-host redirect and halts if disallowed" do
        doc_reader = instance_double(
          SwayLocale::DocumentReader::Document,
          news_sources: [
            {"url" => "https://thebanner.com/politics", "path_policy" => "restrict"},
            {"url" => "https://baltimoresun.com/politics", "path_policy" => "restrict"}
          ]
        )
        allow(SwayLocale::DocumentReader).to receive(:current_for).with(baltimore_locale).and_return(doc_reader)

        initial_url = "https://thebanner.com/politics/initial-slug"
        cross_host_url = "https://baltimoresun.com/politics/final-slug"
        news_article.update_column(:canonical_url, initial_url)

        stub_request(:get, "https://thebanner.com/robots.txt")
          .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "User-agent: *\nAllow: /\n")

        stub_request(:get, "https://baltimoresun.com/robots.txt")
          .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "User-agent: SwayCivic\nDisallow: /politics/\n")

        stub_request(:get, initial_url)
          .to_return(status: 302, headers: {"Location" => cross_host_url})

        described_class.call(bill_news_article: bill_news_article)

        expect(WebMock).to have_requested(:get, initial_url).once
        expect(WebMock).to have_requested(:get, "https://baltimoresun.com/robots.txt").once
        expect(WebMock).not_to have_requested(:get, cross_host_url)

        expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
      end

      it "checks destination host robots.txt on cross-host redirect and halts with zero requests if destination robots returns 404 with CAPTCHA" do
        doc_reader = instance_double(
          SwayLocale::DocumentReader::Document,
          news_sources: [
            {"url" => "https://thebanner.com/politics", "path_policy" => "restrict"},
            {"url" => "https://baltimoresun.com/politics", "path_policy" => "restrict"}
          ]
        )
        allow(SwayLocale::DocumentReader).to receive(:current_for).with(baltimore_locale).and_return(doc_reader)

        initial_url = "https://thebanner.com/politics/initial-slug"
        cross_host_url = "https://baltimoresun.com/politics/final-slug"
        news_article.update_column(:canonical_url, initial_url)

        stub_request(:get, "https://thebanner.com/robots.txt")
          .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "User-agent: *\nAllow: /\n")

        captcha_html = '<html><title>Human Verification</title><body><div class="h-captcha" data-sitekey="test"></div></body></html>'
        stub_request(:get, "https://baltimoresun.com/robots.txt")
          .to_return(status: 404, headers: {"Content-Type" => "text/html"}, body: captcha_html)

        stub_request(:get, initial_url)
          .to_return(status: 302, headers: {"Location" => cross_host_url})

        described_class.call(bill_news_article: bill_news_article)

        expect(WebMock).to have_requested(:get, initial_url).once
        expect(WebMock).to have_requested(:get, "https://baltimoresun.com/robots.txt").once
        expect(WebMock).not_to have_requested(:get, cross_host_url)

        expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
      end

      it "checks destination host robots.txt on cross-host redirect and halts with zero requests if destination robots returns 200 with HTML login fragment" do
        doc_reader = instance_double(
          SwayLocale::DocumentReader::Document,
          news_sources: [
            {"url" => "https://thebanner.com/politics", "path_policy" => "restrict"},
            {"url" => "https://baltimoresun.com/politics", "path_policy" => "restrict"}
          ]
        )
        allow(SwayLocale::DocumentReader).to receive(:current_for).with(baltimore_locale).and_return(doc_reader)

        initial_url = "https://thebanner.com/politics/initial-slug"
        cross_host_url = "https://baltimoresun.com/politics/final-slug"
        news_article.update_column(:canonical_url, initial_url)

        stub_request(:get, "https://thebanner.com/robots.txt")
          .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "User-agent: *\nAllow: /\n")

        login_fragment = '<div><h1>Sign in</h1><form action="/login"><input type="password"><button>Sign in</button></form></div>'
        stub_request(:get, "https://baltimoresun.com/robots.txt")
          .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: login_fragment)

        stub_request(:get, initial_url)
          .to_return(status: 302, headers: {"Location" => cross_host_url})

        described_class.call(bill_news_article: bill_news_article)

        expect(WebMock).to have_requested(:get, initial_url).once
        expect(WebMock).to have_requested(:get, "https://baltimoresun.com/robots.txt").once
        expect(WebMock).not_to have_requested(:get, cross_host_url)

        expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
      end
    end

    describe "efficiency & caching" do
      it "fetches robots.txt at most once per host during multiple operations" do
        robots_txt = <<~ROBOTS
          User-agent: *
          Allow: /politics/
        ROBOTS

        stub_request(:get, "https://thebanner.com/robots.txt")
          .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

        article1_url = "https://thebanner.com/politics/article-1"
        article2_url = "https://thebanner.com/politics/article-2"

        stub_request(:get, article1_url).to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)
        stub_request(:get, article2_url).to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

        bna1 = bill_news_article
        bna1.news_article.update_column(:canonical_url, article1_url)

        article2 = create(:news_article, canonical_url: article2_url, title: "Story 2")
        bna2 = create(:bill_news_article, bill: bill, news_article: article2)

        described_class.call(bill_news_article: bna1)
        described_class.call(bill_news_article: bna2)

        expect(WebMock).to have_requested(:get, "https://thebanner.com/robots.txt").once
        expect(WebMock).to have_requested(:get, article1_url).once
        expect(WebMock).to have_requested(:get, article2_url).once
      end
    end
  end

  describe "(BUG) Keep inaccessible article previews out of synthesis evidence" do
    it "classifies microdata isAccessibleForFree='false' with 100+ char preview as paywalled, skips metadata enrichment, and denies synthesis eligibility" do
      microdata_paywall_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Council Advances Housing Ordinance</title>
            <meta name="author" content="Gated Reporter">
            <meta property="article:published_time" content="2026-03-20T10:00:00Z">
          </head>
          <body>
            <div itemscope itemtype="http://schema.org/NewsArticle">
              <meta itemprop="isAccessibleForFree" content="false">
              <article>
                <h1>Council Advances Housing Ordinance</h1>
                <p>The Baltimore City Council voted on Monday to advance a major housing overhaul affecting multiple neighborhoods. This introductory preview paragraph exceeds one hundred characters in total length.</p>
              </article>
            </div>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: microdata_paywall_html)

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("paywalled")
      expect(version.text).to be_nil
      expect(version.digest).to eq(Digest::SHA256.hexdigest(""))

      news_article.reload
      expect(news_article.author_name).to be_nil
      expect(news_article.published_at).to be_nil

      expect(bill_news_article.eligible_for_synthesis?).to be false
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
      expect(bill_news_article.eligible_for_link?).to be true
    end

    it "classifies dedicated login gate screen as paywalled, skips metadata enrichment, and denies synthesis eligibility" do
      login_gate_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Sign in to your account</title>
            <meta name="author" content="Account Services">
          </head>
          <body>
            <main>
              <h1>Sign in to your account</h1>
              <p>Please enter your email address and password to access your digital subscription and continue reading this story.</p>
              <form action="/login" method="post">
                <label for="email">Email</label>
                <input type="email" id="email" name="email">
                <label for="password">Password</label>
                <input type="password" id="password" name="password">
                <button type="submit">Sign In</button>
              </form>
            </main>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: login_gate_html)

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("paywalled")
      expect(version.text).to be_nil
      expect(news_article.reload.author_name).to be_nil
      expect(bill_news_article.eligible_for_synthesis?).to be false
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
      expect(bill_news_article.eligible_for_link?).to be true
    end

    it "classifies Human Verification challenge screen with hcaptcha script and data-sitekey container as failed" do
      challenge_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Human Verification</title>
            <meta name="author" content="Security Team">
            <script src="https://js.hcaptcha.com/1/api.js" async defer></script>
          </head>
          <body>
            <main>
              <h1>Human Verification</h1>
              <div id="custom-hcaptcha-container" data-sitekey="10000000-ffff-ffff-ffff-000000000001"></div>
              <p>Please confirm that you are not a robot before continuing to this website and reading the requested story.</p>
            </main>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: challenge_html)

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
      expect(news_article.reload.author_name).to be_nil
      expect(bill_news_article.eligible_for_synthesis?).to be false
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
      expect(bill_news_article.eligible_for_link?).to be true
    end

    it "extracts clean text and enriches metadata when a readable article has an unrelated footer login form" do
      article_with_footer_login_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Council Expands Parks Funding</title>
            <meta name="author" content="Jane Reporter">
            <meta property="article:published_time" content="2026-03-25T12:00:00Z">
          </head>
          <body>
            <header>
              <nav>
                <a href="/">Home</a>
                <a href="/login">Sign in to your account</a>
              </nav>
            </header>
            <main>
              <article>
                <h1>Council Expands Parks Funding</h1>
                <p>The Baltimore City Council approved a new budget allocation for neighborhood parks on Wednesday.</p>
                <p>The measure provides five million dollars for playground equipment and trail maintenance across all council districts.</p>
              </article>
            </main>
            <footer>
              <p>Already a subscriber? <a href="/login">Sign in to your account</a></p>
              <form action="/login" method="post">
                <input type="password" name="password">
                <button type="submit">Sign In</button>
              </form>
            </footer>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: article_with_footer_login_html)

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("extracted")
      expect(version.text).to include("The Baltimore City Council approved a new budget allocation")
      expect(version.text).not_to include("Sign in to your account")
      expect(news_article.reload.author_name).to eq("Jane Reporter")
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be true
    end

    it "extracts clean text and enriches metadata when a readable article has an unrelated footer CAPTCHA widget" do
      article_with_footer_captcha_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Port Investment Project Moves Forward</title>
            <meta name="author" content="Maritime Reporter">
            <meta property="article:published_time" content="2026-03-25T12:00:00Z">
            <script src="https://js.hcaptcha.com/1/api.js" async defer></script>
          </head>
          <body>
            <main>
              <article>
                <h1>Port Investment Project Moves Forward</h1>
                <p>A multi-million dollar infrastructure project at the Port of Baltimore was given final approval today.</p>
                <p>Officials announced that construction will begin early next spring, creating hundreds of maritime jobs.</p>
              </article>
            </main>
            <footer>
              <div class="newsletter-signup">
                <p>Subscribe to our newsletter</p>
                <div class="h-captcha" data-sitekey="10000000-ffff-ffff-ffff-000000000001"></div>
              </div>
            </footer>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: article_with_footer_captcha_html)

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("extracted")
      expect(version.text).to include("A multi-million dollar infrastructure project at the Port of Baltimore")
      expect(news_article.reload.author_name).to eq("Maritime Reporter")
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be true
    end

    it "extracts clean text for readable articles declaring microdata isAccessibleForFree='true'" do
      accessible_microdata_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Public Health Department Launches Air Monitoring Network</title>
            <meta name="author" content="Health Reporter">
          </head>
          <body>
            <article itemscope itemtype="https://schema.org/NewsArticle">
              <meta itemprop="isAccessibleForFree" content="true">
              <h1 itemprop="headline">Public Health Department Launches Air Monitoring Network</h1>
              <p>City health officials installed thirty new environmental monitoring sensors across industrial neighborhoods today to track airborne particulates in real time.</p>
              <p>The sensor data will be publicly accessible through an open dashboard updated every fifteen minutes.</p>
              <p>Neighborhood associations praised the transparency initiative, noting that particulate tracking had previously been limited to regional EPA stations.</p>
            </article>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: accessible_microdata_html)

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("extracted")
      expect(version.text).to include("Public Health Department Launches Air Monitoring Network")
      expect(news_article.reload.author_name).to eq("Health Reporter")
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be true
    end

    it "extracts clean text when legitimate reporting quotes barrier phrases" do
      reporting_quoting_barriers_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Advocates Challenge State Portal Verification Hurdles</title>
            <meta name="author" content="Civic Reporter">
          </head>
          <body>
            <main>
              <article>
                <h1>Advocates Challenge State Portal Verification Hurdles</h1>
                <p>Civil rights advocates filed a formal petition on Tuesday challenging new identity screening requirements on the state benefit portal.</p>
                <p>The complaint highlighted prompts stating "Please confirm that you are not a robot before continuing" and pages reading "Sign in to your account" that repeatedly locked out visually impaired users.</p>
                <p>State officials agreed to review the digital intake system and provide alternative telephone verification within thirty days.</p>
              </article>
            </main>
          </body>
        </html>
      HTML

      news_article.update!(author_name: nil, published_at: nil)
      stub_request(:get, canonical_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: reporting_quoting_barriers_html)

      described_class.call(bill_news_article: bill_news_article)

      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("extracted")
      expect(version.text).to include("Civil rights advocates filed a formal petition")
      expect(version.text).to include('prompts stating "Please confirm that you are not a robot before continuing"')
      expect(news_article.reload.author_name).to eq("Civic Reporter")
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be true
    end

    context "with long previews and active access barriers" do
      it "rejects a long preview (>= 250 chars) followed by an active subscribe gate without known CSS" do
        preview_text = "Council members debated housing legislation at their meeting. The proposal changes how vacant properties can be developed and establishes a new review process. Supporters say the measure could expand affordable housing while opponents question the costs and the effect on existing residents. "
        html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Housing reform</title>
              <meta name="author" content="Barrier author">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <article>
                <p>#{preview_text}</p>
                <section>
                  <h2>Subscribe to continue</h2>
                  <p>Unlock the rest of this story with a paid account.</p>
                  <a href="/subscribe">Choose your subscription</a>
                </section>
              </article>
            </body>
          </html>
        HTML

        news_article.update!(author_name: nil, published_at: nil)
        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("paywalled")
        expect(version.usable_text?).to be false
        expect(version.text).to be_blank
        expect(news_article.reload.author_name).to be_nil
        expect(news_article.published_at).to be_nil
        expect(bill_news_article.eligible_for_synthesis?).to be false

        bill_news_article.update!(approved: true)
        expect(bill_news_article.eligible_for_synthesis?).to be false
        expect(bill_news_article.eligible_for_link?).to be true
      end

      it "rejects a long preview followed by a main-area subscription password form" do
        preview_text = "Council members debated housing legislation at their meeting. The proposal changes how vacant properties can be developed and establishes a new review process. Supporters say the measure could expand affordable housing while opponents question the costs and the effect on existing residents. "
        html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Housing reform</title>
              <meta name="author" content="Barrier author">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <main>
                <article>
                  <p>#{preview_text}</p>
                </article>
                <form action="/login">
                  <h2>Subscriber sign in</h2>
                  <p>Sign in to read the rest of this story.</p>
                  <input type="password">
                  <button>Sign in</button>
                </form>
              </main>
            </body>
          </html>
        HTML

        news_article.update!(author_name: nil, published_at: nil)
        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("paywalled")
        expect(version.usable_text?).to be false
        expect(version.text).to be_blank
        expect(news_article.reload.author_name).to be_nil
        expect(news_article.published_at).to be_nil
        expect(bill_news_article.eligible_for_synthesis?).to be false
      end

      it "rejects a long preview with an active text CAPTCHA verification gate" do
        preview_text = "Council members debated housing legislation at their meeting. The proposal changes how vacant properties can be developed and establishes a new review process. Supporters say the measure could expand affordable housing while opponents question the costs and the effect on existing residents. "
        html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Housing reform</title>
              <meta name="author" content="Barrier author">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <main>
                <article>
                  <p>#{preview_text}</p>
                </article>
                <section>
                  <h2>Verify you are human</h2>
                  <p>Please solve the captcha to continue reading.</p>
                  <form action="/verify">
                    <img src="/puzzle.png" alt="Verification image">
                    <input name="answer">
                    <button>Verify</button>
                  </form>
                </section>
              </main>
            </body>
          </html>
        HTML

        news_article.update!(author_name: nil, published_at: nil)
        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.usable_text?).to be false
        expect(version.text).to be_blank
        expect(news_article.reload.author_name).to be_nil
        expect(news_article.published_at).to be_nil
        expect(bill_news_article.eligible_for_synthesis?).to be false
      end

      it "ensures an opinion article behind an active barrier cannot supply testimony and retains existing metadata" do
        preview_text = "Council members debated housing legislation at their meeting. The proposal changes how vacant properties can be developed and establishes a new review process. Supporters say the measure could expand affordable housing while opponents question the costs and the effect on existing residents. "
        html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Editorial: New Housing Plan</title>
              <meta name="author" content="Barrier Scraper">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <article>
                <p>#{preview_text}</p>
                <section>
                  <h2>Subscribe to continue</h2>
                  <p>Unlock the rest of this story with a paid account.</p>
                  <a href="/subscribe">Choose your subscription</a>
                </section>
              </article>
            </body>
          </html>
        HTML

        news_article.update!(
          article_kind: "op_ed",
          author_name: "Original Columnist",
          published_at: 1.day.ago
        )
        bill_news_article.update!(approved: true, stance: "support")

        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("paywalled")
        expect(version.usable_text?).to be false
        expect(bill_news_article.eligible_for_testimony?).to be false
        expect(news_article.reload.author_name).to eq("Original Columnist")
      end

      it "rejects subscribe barriers across paragraph lengths below, at, and above the former 250-character cutoff" do
        [200, 250, 300].each do |char_count|
          filler = "Word " * ((char_count / 5) - 1)
          preview = filler.ljust(char_count, "a")

          html = <<~HTML
            <!DOCTYPE html>
            <html>
              <head>
                <title>Housing reform</title>
              </head>
              <body>
                <article>
                  <p>#{preview}</p>
                  <section>
                    <h2>Subscribe to continue</h2>
                    <p>Unlock the rest of this story with a paid account.</p>
                    <a href="/subscribe">Choose your subscription</a>
                  </section>
                </article>
              </body>
            </html>
          HTML

          stub_request(:get, canonical_url)
            .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

          described_class.call(bill_news_article: bill_news_article)
          version = bill_news_article.reload.current_text_version
          expect(version.extraction_status).to eq("paywalled"), "Expected char count #{char_count} to be paywalled"
          expect(version.usable_text?).to be false
        end
      end

      it "extracts an ordinary complete readable article control cleanly" do
        preview_text = "Council members debated housing legislation at their meeting. The proposal changes how vacant properties can be developed and establishes a new review process. Supporters say the measure could expand affordable housing while opponents question the costs and the effect on existing residents. "
        html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Housing reform</title>
              <meta name="author" content="Legitimate Reporter">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <article>
                <p>#{preview_text}</p>
              </article>
            </body>
          </html>
        HTML

        news_article.update!(author_name: nil, published_at: nil)
        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
        expect(version.usable_text?).to be true
        expect(version.text).to include("Council members debated housing legislation")
        expect(news_article.reload.author_name).to eq("Legitimate Reporter")
        bill_news_article.update!(approved: true)
        expect(bill_news_article.eligible_for_synthesis?).to be true
        expect(bill_news_article.eligible_for_link?).to be true
      end

      it "rejects an article preview followed by a known paywall inside an article aside" do
        preview_text = "Council members debated housing legislation at their meeting. The proposal changes how vacant properties can be developed and establishes a new review process. Supporters say the measure could expand affordable housing while opponents question costs. "
        html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Housing reform</title>
              <meta name="author" content="Barrier author">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <article>
                <p>#{preview_text}</p>
                <aside class="paywall">
                  <h2>Subscribe to continue</h2>
                  <p>This article is for subscribers only.</p>
                  <a href="/subscribe">Subscribe</a>
                </aside>
              </article>
            </body>
          </html>
        HTML

        news_article.update!(author_name: nil, published_at: nil)
        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("paywalled")
        expect(version.usable_text?).to be false
        expect(version.text).to be_blank
        expect(news_article.reload.author_name).to be_nil
        expect(news_article.published_at).to be_nil
        expect(bill_news_article.eligible_for_synthesis?).to be false

        bill_news_article.update!(approved: true)
        expect(bill_news_article.eligible_for_synthesis?).to be false
        expect(bill_news_article.eligible_for_link?).to be true
      end

      it "rejects an article preview followed by an active captcha inside an article aside" do
        preview_text = "Council members debated housing legislation at their meeting. The proposal changes how vacant properties can be developed and establishes a new review process. Supporters say the measure could expand affordable housing while opponents question costs. "
        html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Housing reform</title>
              <meta name="author" content="Barrier author">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <article>
                <p>#{preview_text}</p>
                <aside>
                  <h2>Verify you are human</h2>
                  <div class="h-captcha" data-sitekey="test"></div>
                </aside>
              </article>
            </body>
          </html>
        HTML

        news_article.update!(author_name: nil, published_at: nil)
        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.usable_text?).to be false
        expect(version.text).to be_blank
        expect(news_article.reload.author_name).to be_nil
        expect(news_article.published_at).to be_nil
        expect(bill_news_article.eligible_for_synthesis?).to be false

        bill_news_article.update!(approved: true)
        expect(bill_news_article.eligible_for_synthesis?).to be false
        expect(bill_news_article.eligible_for_link?).to be true
      end

      it "rejects a paragraph-only browser challenge page with long instructions" do
        instruction_text = "Please wait while your request is being verified. We are checking your browser before accessing this page. This process is automatic. You will be redirected to the requested story once verification completes. Please keep this window open."
        html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Housing reform</title>
              <meta name="author" content="Barrier author">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <main>
                <p>#{instruction_text}</p>
              </main>
            </body>
          </html>
        HTML

        news_article.update!(author_name: nil, published_at: nil)
        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("failed")
        expect(version.usable_text?).to be false
        expect(version.text).to be_blank
        expect(news_article.reload.author_name).to be_nil
        expect(news_article.published_at).to be_nil
        expect(bill_news_article.eligible_for_synthesis?).to be false

        bill_news_article.update!(approved: true)
        expect(bill_news_article.eligible_for_synthesis?).to be false
        expect(bill_news_article.eligible_for_link?).to be true
      end

      it "rejects browser verification instructions across lengths below, at, and above MIN_TEXT_CHARS" do
        news_article.update!(author_name: nil, published_at: nil)

        variations = [
          "Please wait while we verify your browser",
          "Please wait while your request is being verified!!",
          "Please wait while your request is being verified. We are checking your browser before accessing now."
        ]

        variations.each do |instruction|
          html = <<~HTML
            <!DOCTYPE html>
            <html>
              <head>
                <title>Housing reform</title>
                <meta name="author" content="Barrier author">
                <meta property="article:published_time" content="2026-03-15T12:00:00Z">
              </head>
              <body>
                <main>
                  <p>#{instruction}</p>
                </main>
              </body>
            </html>
          HTML

          stub_request(:get, canonical_url)
            .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

          described_class.call(bill_news_article: bill_news_article)

          version = bill_news_article.reload.current_text_version
          expect(version.extraction_status).to eq("failed"), "Expected '\#{instruction}' to be failed"
          expect(version.usable_text?).to be false
          expect(version.text).to be_blank
          expect(news_article.reload.author_name).to be_nil
          expect(news_article.published_at).to be_nil
        end
      end

      it "extracts clean text when an article contains valid non-barrier aside notes" do
        preview_text = "Council members debated housing legislation at their meeting. The proposal changes how vacant properties can be developed and establishes a new review process. Supporters say the measure could expand affordable housing while opponents question costs. "
        html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Housing reform</title>
              <meta name="author" content="Legitimate Reporter">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <article>
                <p>#{preview_text}</p>
                <aside class="editorial-note">
                  <p>Editor's note: This story was updated to reflect revised hearing testimony.</p>
                </aside>
                <p>Supporters say the measure could expand affordable housing while opponents question costs.</p>
              </article>
            </body>
          </html>
        HTML

        news_article.update!(author_name: nil, published_at: nil)
        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
        expect(version.usable_text?).to be true
        expect(version.text).to include("Council members debated housing legislation")
        expect(news_article.reload.author_name).to eq("Legitimate Reporter")
        expect(news_article.published_at).not_to be_nil
        bill_news_article.update!(approved: true)
        expect(bill_news_article.eligible_for_synthesis?).to be true
        expect(bill_news_article.eligible_for_link?).to be true
      end

      it "extracts clean text when peripheral header or sidebar contains newsletter or login widgets" do
        preview_text = "Council members debated housing legislation at their meeting. The proposal changes how vacant properties can be developed and establishes a new review process. Supporters say the measure could expand affordable housing while opponents question costs. "
        html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Housing reform</title>
              <meta name="author" content="Legitimate Reporter">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <header>
                <form action="/login"><input type="password"><button>Login</button></form>
              </header>
              <aside class="newsletter">
                <form action="/newsletter">
                  <div class="g-recaptcha" data-sitekey="recaptcha-key"></div>
                </form>
              </aside>
              <main>
                <article>
                  <p>#{preview_text}</p>
                </article>
              </main>
            </body>
          </html>
        HTML

        news_article.update!(author_name: nil, published_at: nil)
        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
        expect(version.usable_text?).to be true
        expect(version.text).to include("Council members debated housing legislation")
        expect(news_article.reload.author_name).to eq("Legitimate Reporter")
        bill_news_article.update!(approved: true)
        expect(bill_news_article.eligible_for_synthesis?).to be true
        expect(bill_news_article.eligible_for_link?).to be true
      end

      it "extracts clean text when an article quotes barrier and verification discussions" do
        html = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Anti-Bot Hearing</title>
              <meta name="author" content="Civic Reporter">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <article>
                <h1>Legislative Committee Examines Verification Challenges</h1>
                <p>The House Oversight Committee held a comprehensive hearing yesterday on automated bot mitigation practices employed by state agencies.</p>
                <p>Witnesses testified about frequent user prompts requiring citizens to "confirm that you are not a robot" or "verify you are human".</p>
                <p>Agency directors explained that distributed denial-of-service traffic surged significantly over the preceding fiscal quarter.</p>
                <p>Consumer advocates presented findings showing how automated challenges disproportionately disrupt access for citizens using screen readers.</p>
              </article>
            </body>
          </html>
        HTML

        news_article.update!(author_name: nil, published_at: nil)
        stub_request(:get, canonical_url)
          .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: html)

        described_class.call(bill_news_article: bill_news_article)

        version = bill_news_article.reload.current_text_version
        expect(version.extraction_status).to eq("extracted")
        expect(version.usable_text?).to be true
        expect(version.text).to include("Legislative Committee Examines Verification Challenges")
        expect(version.text).to include('prompts requiring citizens to "confirm that you are not a robot"')
        expect(news_article.reload.author_name).to eq("Civic Reporter")
        bill_news_article.update!(approved: true)
        expect(bill_news_article.eligible_for_synthesis?).to be true
      end
    end
  end

  describe "(BUG) Honor publisher robots directives during path matching" do
    before do
      NewsArticleRobotsPolicy.reset_cache!
    end

    it "halts retrieval with zero article requests when path with percent-encoded UTF-8 matches literal UTF-8 Disallow" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /café/
      ROBOTS

      article_url = "https://thebanner.com/caf%C3%A9/story"
      news_article.update!(canonical_url: article_url)

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      stub_request(:get, article_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_disallowed,
          url: article_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      expect(WebMock).not_to have_requested(:get, article_url)
      expect(WebMock).to have_requested(:get, "https://thebanner.com/robots.txt").once

      version = bill_news_article.reload.current_text_version
      expect(version.origin).to eq("retrieved")
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
      expect(version.digest).to eq(Digest::SHA256.hexdigest(""))

      expect(bill_news_article.eligible_for_synthesis?).to be false
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_synthesis?).to be false
      expect(bill_news_article.eligible_for_link?).to be true
    end

    it "halts retrieval with zero article requests when redirect leads to path disallowed by literal UTF-8 rule" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /café/
      ROBOTS

      redirect_target_url = "https://thebanner.com/caf%C3%A9/story"

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      stub_request(:get, canonical_url)
        .to_return(status: 301, headers: {"Location" => redirect_target_url})

      stub_request(:get, redirect_target_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_disallowed,
          url: redirect_target_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).to have_requested(:get, canonical_url).once
      expect(WebMock).not_to have_requested(:get, redirect_target_url)
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
    end

    it "halts retrieval with zero article requests on empty Disallow boundary retention failure scenario" do
      robots_txt = <<~ROBOTS
        User-agent: SwayCivic
        Disallow:

        User-agent: OtherBot
        Allow: /private/

        User-agent: SwayCivic
        Disallow: /private/
      ROBOTS

      article_url = "https://thebanner.com/private/story"
      news_article.update!(canonical_url: article_url)

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      stub_request(:get, article_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_disallowed,
          url: article_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      expect(WebMock).not_to have_requested(:get, article_url)
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.text).to be_nil
    end

    it "halts retrieval with zero article requests when robots.txt uses CR-only line endings" do
      article_url = "https://thebanner.com/politics/housing"
      news_article.update!(canonical_url: article_url)

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "User-agent: *\rDisallow: /politics/\r")

      stub_request(:get, article_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_disallowed,
          url: article_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      expect(WebMock).not_to have_requested(:get, article_url)
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.usable_text?).to be false
      expect(bill_news_article.eligible_for_synthesis?).to be false
      bill_news_article.update!(approved: true)
      expect(bill_news_article.eligible_for_link?).to be true
    end

    it "halts retrieval with zero article requests when robots.txt is prefixed with a UTF-8 BOM" do
      article_url = "https://thebanner.com/politics/housing"
      news_article.update!(canonical_url: article_url)

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "\xEF\xBB\xBFUser-agent: *\nDisallow: /politics/\n")

      stub_request(:get, article_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_disallowed,
          url: article_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      expect {
        described_class.call(bill_news_article: bill_news_article)
      }.to change(NewsArticleTextVersion, :count).by(1)

      expect(WebMock).not_to have_requested(:get, article_url)
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("failed")
      expect(version.usable_text?).to be false
    end

    it "halts retrieval with zero article requests when redirect target is denied by CR-only robots.txt" do
      initial_url = "https://thebanner.com/politics/initial"
      redirect_target_url = "https://thebanner.com/restricted/housing"
      news_article.update!(canonical_url: initial_url)

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "User-agent: *\rDisallow: /restricted/\r")

      stub_request(:get, initial_url)
        .to_return(status: 301, headers: {"Location" => redirect_target_url})

      stub_request(:get, redirect_target_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_disallowed,
          url: redirect_target_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).to have_requested(:get, initial_url).once
      expect(WebMock).not_to have_requested(:get, redirect_target_url)
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
    end

    it "halts retrieval with zero article requests when redirect target is denied by BOM-prefixed robots.txt" do
      initial_url = "https://thebanner.com/politics/initial"
      redirect_target_url = "https://thebanner.com/restricted/housing"
      news_article.update!(canonical_url: initial_url)

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "\uFEFFUser-agent: *\nDisallow: /restricted/\n")

      stub_request(:get, initial_url)
        .to_return(status: 301, headers: {"Location" => redirect_target_url})

      stub_request(:get, redirect_target_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      expect(SwayLogging).to receive(:warn).with(
        "news_article_text_fetch.robots_refused",
        hash_including(
          refusal_reason: :robots_disallowed,
          url: redirect_target_url,
          news_article_id: news_article.id,
          bill_id: bill.id
        )
      )

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).to have_requested(:get, initial_url).once
      expect(WebMock).not_to have_requested(:get, redirect_target_url)
      expect(bill_news_article.reload.current_text_version.extraction_status).to eq("failed")
    end

    it "successfully retrieves article when allowed by CR-only or BOM-prefixed robots directives" do
      article_url = "https://thebanner.com/politics/housing"
      news_article.update!(canonical_url: article_url)

      stub_request(:get, "https://thebanner.com/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "\uFEFFUser-agent: *\rDisallow: /politics/\rAllow: /politics/housing\r")

      stub_request(:get, article_url)
        .to_return(status: 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: valid_html_body)

      described_class.call(bill_news_article: bill_news_article)

      expect(WebMock).to have_requested(:get, article_url).once
      version = bill_news_article.reload.current_text_version
      expect(version.extraction_status).to eq("extracted")
      expect(version.usable_text?).to be true
      expect(version.text).to be_present
    end
  end
end
