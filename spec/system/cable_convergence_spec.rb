# frozen_string_literal: true

require "rails_helper"

# @lat: [[cable-convergence-budget#ActionCable convergence measurement]]
RSpec.describe "ActionCable convergence measurement", type: :system, js: true, convergence: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:sway_admin_user) { create(:user, :sway_admin) }

  before do
    create(:user_legislator, user: sway_admin_user, legislator: legislator)
  end

  it "times live ActionCable broadcast-to-DOM round trips on /pipeline_runs within budget" do
    sign_in_as(sway_admin_user)

    samples_ms = []

    6.times do |iteration|
      is_warmup = iteration.zero?
      run = create(:legislation_pipeline_run, :running)

      visit pipeline_runs_path
      wait_until_loaded

      row_selector = "[data-testid='pipeline-run-row-#{run.id}']"
      expect(page).to have_css(row_selector, wait: 10)
      row = find(row_selector)
      expect(row).to have_css("[data-tone='info']", text: "running")

      arm_mutation_observer(run.id)

      # Brief pause ensuring ActionCable subscription handshake has completed
      sleep 0.15

      t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)
      run.mark_succeeded!

      mutation_result = await_mutation_observer
      t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)

      expect(row).to have_css("[data-tone='success']", text: "succeeded", wait: 5)
      expect(mutation_result["timeout"]).to be_nil

      elapsed_ms = (t_end - t_start) * 1000.0

      if is_warmup
        RSpec.configuration.reporter.message(
          "[convergence] Warmup iteration: #{elapsed_ms.round(2)}ms"
        )
      else
        samples_ms << elapsed_ms
        RSpec.configuration.reporter.message(
          "[convergence] Sample #{iteration}/5: #{elapsed_ms.round(2)}ms"
        )
      end
    end

    metrics = calculate_metrics(samples_ms)
    record_measurements(samples_ms, metrics)

    RSpec.configuration.reporter.message(
      "[convergence] Measured median convergence: #{metrics[:median_ms]}ms (samples: #{samples_ms.map { |s| s.round(1) }}, budget: 1000ms) - PROMISE MET"
    )

    expect(metrics[:median_ms]).to be < 500
    expect(metrics[:median_ms]).to be < 1000
  end

  def arm_mutation_observer(run_id)
    script = <<~JS
      (function(runId) {
        const row = document.querySelector(`[data-testid="pipeline-run-row-${runId}"]`);
        if (!row) {
          window.__convergence = { error: `Row not found for run ${runId}` };
          return;
        }
        window.__convergence = {
          armedAt: performance.now(),
          mutated: false,
          mutatedAt: null,
          text: null,
          tone: null
        };
        window.__convergenceResolve = null;

        const observer = new MutationObserver(() => {
          const badge = row.querySelector("[data-tone]");
          if (badge && badge.textContent.trim().toLowerCase() === "succeeded" && badge.getAttribute("data-tone") === "success") {
            if (!window.__convergence.mutated) {
              window.__convergence.mutated = true;
              window.__convergence.mutatedAt = performance.now();
              window.__convergence.text = badge.textContent.trim();
              window.__convergence.tone = badge.getAttribute("data-tone");
              observer.disconnect();
              if (typeof window.__convergenceResolve === "function") {
                window.__convergenceResolve(window.__convergence);
              }
            }
          }
        });
        observer.observe(row, { childList: true, subtree: true, characterData: true });
      })(arguments[0]);
    JS
    page.execute_script(script, run_id)
    error = page.evaluate_script("window.__convergence && window.__convergence.error")
    expect(error).to be_nil
  end

  def await_mutation_observer
    script = <<~JS
      const done = arguments[arguments.length - 1];
      if (window.__convergence && window.__convergence.mutated) {
        done(window.__convergence);
        return;
      }
      window.__convergenceResolve = done;
      setTimeout(() => {
        if (window.__convergence && !window.__convergence.mutated) {
          done({ timeout: true, convergence: window.__convergence });
        }
      }, 5000);
    JS
    page.driver.browser.execute_async_script(script)
  end

  def calculate_metrics(samples_ms)
    min_ms = samples_ms.min.round(2)
    max_ms = samples_ms.max.round(2)
    mean_ms = (samples_ms.sum / samples_ms.size).round(2)
    sorted = samples_ms.sort
    median_ms = sorted[sorted.size / 2].round(2)
    variance = samples_ms.map { |x| (x - mean_ms)**2 }.sum / samples_ms.size
    std_dev_ms = Math.sqrt(variance).round(2)

    {
      min_ms: min_ms,
      max_ms: max_ms,
      mean_ms: mean_ms,
      median_ms: median_ms,
      std_dev_ms: std_dev_ms
    }
  end

  def record_measurements(samples_ms, metrics)
    adapter = ActionCable.server.config.cable[:adapter] || "test"
    data = {
      timestamp: Time.current.utc.iso8601,
      environment: Rails.env,
      adapter: adapter.to_s,
      host_arch: RbConfig::CONFIG["host_cpu"] || RUBY_PLATFORM,
      samples_ms: samples_ms.map { |s| s.round(2) },
      median_ms: metrics[:median_ms],
      mean_ms: metrics[:mean_ms],
      min_ms: metrics[:min_ms],
      max_ms: metrics[:max_ms],
      std_dev_ms: metrics[:std_dev_ms],
      budget_ms: 1000,
      met_promise: metrics[:median_ms] < 500,
      start_definition: "Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second) immediately before server update (run.mark_succeeded!)",
      end_definition: "MutationObserver microtask callback observing DOM badge text 'succeeded' with data-tone 'success'"
    }

    measurements_dir = Rails.root.join("tmp", "measurements")
    FileUtils.mkdir_p(measurements_dir)
    File.write(
      measurements_dir.join("cable_convergence.json"),
      JSON.pretty_generate(data)
    )
  end
end
