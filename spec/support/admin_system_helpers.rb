# frozen_string_literal: true

module AdminSystemHelpers
  # Sign in as the given user through a sign-in route that exists only in tests.
  # Call this AFTER visiting a page, so the browser session already exists.
  def sign_in_as(user)
    visit root_path
    # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#A reused browser keeps an earlier example's cookies]]
    wait_until_loaded
    page.driver.browser.manage.delete_all_cookies
    result =
      browser_json_request("POST", "/test/sessions", {user_id: user.id})
    expect(result.fetch("status")).to eq(200)
    expect(result.dig("body", "ok")).to eq(true)
  end

  # @lat: [[bill-creator-tab-url-routing#Why sway_locale_id is required in system-spec navigation helpers]]
  def navigate_to_llm_accordion(bill)
    visit "/admin/bill_creator/#{bill.id}/summary?sway_locale_id=#{bill.sway_locale_id}"
    wait_until_loaded
  end
  alias_method :navigate_to_summary_tab, :navigate_to_llm_accordion

  def navigate_to_positions_tab(bill)
    visit "/admin/bill_creator/#{bill.id}/positions?sway_locale_id=#{bill.sway_locale_id}"
    wait_until_loaded
  end

  # @lat: [[bill-creator-tab-url-routing#Why sway_locale_id is required in system-spec navigation helpers]]
  def navigate_to_pipeline_llm_tab(bill)
    visit "/admin/bill_creator/#{bill.id}/pipeline?sway_locale_id=#{bill.sway_locale_id}"
    wait_until_loaded
  end

  # @lat: [[admin-org-positions-spec-design#The click_testid fix and where a shadcn Select renders its options]]
  def click_testid(testid, **find_opts)
    element = find("[data-testid='#{testid}']", **find_opts)
    page.execute_script(
      "arguments[0].scrollIntoView({block: 'center', behavior: 'instant'});",
      element.native
    )
    begin
      element.click
    rescue Selenium::WebDriver::Error::ElementNotInteractableError,
      Selenium::WebDriver::Error::ElementClickInterceptedError
      page.execute_script("arguments[0].click();", element.native)
    end
    element
  end

  # @lat: [[stub-pipeline-success-two-calls#Why stub_pipeline_success answers two different LLM calls differently]]
  def stub_pipeline_success(
    _bill,
    summary_text: "Test LLM summary",
    org_positions: []
  )
    summary_payload = {
      "summary_markdown" => summary_text,
      "full_breakdown_markdown" => "## Section 1\nDetailed breakdown text."
    }
    positions_payload = {"draft_org_positions" => org_positions}

    openai_client = instance_double(OpenAI::Client)
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)
    allow(openai_client).to receive(:chat) do |parameters:|
      body =
        if parameters.dig(:response_format, :json_schema, :name) == "bill_positions"
          positions_payload
        else
          summary_payload
        end
      {"choices" => [{"message" => {"content" => body.to_json}}]}
    end
  end

  def stub_pipeline_failure
    openai_client = instance_double(OpenAI::Client)
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)
    allow(openai_client).to receive(:chat).and_raise(StandardError, "llama.cpp unreachable")
  end

  def cleanup_summary_files(bill)
    FileUtils.rm_f(
      Rails.root.join("legislation/summaries/#{bill.external_id}.json")
    )
  end

  # Reuse the browser_json_request pattern from webauthn_passkey_spec.rb
  def browser_json_request(method, path, payload)
    script = <<~JS
      const method = arguments[0];
      const path = arguments[1];
      const payload = arguments[2];
      const done = arguments[arguments.length - 1];

      const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || "";

      fetch(path, {
        method,
        credentials: "same-origin",
        redirect: "manual",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "X-XSRF-Token": csrfToken,
        },
        body: JSON.stringify(payload),
      })
        .then(async (response) => {
          if (response.type === "opaqueredirect") {
            done({ status: 303, body: {} });
            return;
          }
          const text = await response.text();
          let body;
          try {
            body = text ? JSON.parse(text) : {};
          } catch (_error) {
            body = { raw: text };
          }
          done({ status: response.status, body });
        })
        .catch((error) => done({ error: String(error) }));
    JS

    result =
      page.driver.browser.execute_async_script(script, method, path, payload)
    raise "Browser request failed: #{result["error"]}" if result["error"]
    result
  end
end

RSpec.configure { |config| config.include AdminSystemHelpers, type: :system }
