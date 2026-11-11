# frozen_string_literal: true

# @lat: [[system-spec-service-worker-stub#Why a leftover real service worker is cleared before the stub goes in]]
module ServiceWorkerStub
  # @lat: [[system-spec-service-worker-stub#Why a leftover real service worker is cleared before the stub goes in]]
  SLOW_LINK_LATENCY_MS = 750
  SLOW_LINK_DOWNLOAD_BYTES_PER_SECOND = 24_000
  SLOW_LINK_UPLOAD_BYTES_PER_SECOND = 24_000
  # @lat: [[system-spec-service-worker-stub#Why a leftover real service worker is cleared before the stub goes in]]
  def clear_real_service_workers!
    server = page.server
    origin = "http://#{server.host}:#{server.port}"
    page.driver.browser.execute_cdp(
      "Storage.clearDataForOrigin",
      origin: origin,
      storageTypes: "service_workers,cache_storage"
    )
  rescue
    # CDP may be gone mid-teardown, or missing on a non-Chromium driver; ignore.
  end

  def inject_service_worker_stub!(endpoint: "https://fcm.googleapis.com/fcm/send/TEST-STUB-000")
    clear_real_service_workers!
    # @lat: [[system-spec-service-worker-stub#Why the stub copies exactly these methods, and why the active worker matters]]
    script = <<~JS
      var __swayStubSubscription = {
        endpoint: #{endpoint.to_json},
        getKey: function() { return new ArrayBuffer(8); },
        unsubscribe: function() { return Promise.resolve(true); },
      };
      // PushNotificationsPanel.registerServiceWorker waits for an *active*
      // ServiceWorker before calling pushManager.subscribe(). Without this
      // active handle the panel times out, never POSTs the subscription, and
      // the UI never flips to "Disable on this device" — failing
      // notification_delivery_spec at the wait_for "Disable on this device".
      var __swayStubActiveWorker = {
        state: "activated",
        scriptURL: "about:blank",
        postMessage: function() {},
        addEventListener: function() {},
        removeEventListener: function() {},
      };
      var __swayStubRegistration = {
        active: __swayStubActiveWorker,
        installing: null,
        waiting: null,
        pushManager: {
          getSubscription: function() { return Promise.resolve(__swayStubSubscription); },
          subscribe: function() { return Promise.resolve(__swayStubSubscription); },
        },
        addEventListener: function() {},
        removeEventListener: function() {},
      };
      Object.defineProperty(navigator, "serviceWorker", {
        value: {
          register: function() { return Promise.resolve(__swayStubRegistration); },
          ready: Promise.resolve(__swayStubRegistration),
          getRegistration: function() { return Promise.resolve(__swayStubRegistration); },
          addEventListener: function() {},
          removeEventListener: function() {},
          controller: null,
        },
        configurable: true,
        writable: true,
      });
      Object.defineProperty(window, "Notification", {
        value: { requestPermission: function() { return Promise.resolve("granted"); } },
        configurable: true,
        writable: true,
      });
      window.VAPID_PUBLIC_KEY = "test-vapid-public-key";
    JS

    result = page.driver.browser.execute_cdp(
      "Page.addScriptToEvaluateOnNewDocument",
      source: script
    )
    script_ids = @sway_stub_script_ids || []
    script_ids << result["identifier"] if result.is_a?(Hash) && result["identifier"]
    @sway_stub_script_ids = script_ids
  end

  # @lat: [[system-spec-service-worker-stub#Why a leftover real service worker is cleared before the stub goes in]]
  def clear_service_worker_stub!
    script_ids = @sway_stub_script_ids
    return if script_ids.nil?

    script_ids.each do |identifier|
      page.driver.browser.execute_cdp(
        "Page.removeScriptToEvaluateOnNewDocument",
        identifier: identifier
      )
    rescue
      # Browser may already be reset between examples; ignore.
    end
    @sway_stub_script_ids = [] #: Array[untyped]
  end

  # @lat: [[system-spec-service-worker-stub#Why a leftover real service worker is cleared before the stub goes in]]

  def wait_for_sw!(timeout_seconds: 10)
    Timeout.timeout(timeout_seconds) do
      loop do
        ready = page.evaluate_script("navigator.serviceWorker && !!navigator.serviceWorker.controller")
        break if ready

        sleep 0.1
      end
    end
  end

  def go_offline!
    set_network_conditions(offline: true)
  end

  def go_online!
    set_network_conditions(offline: false)
  end

  # @lat: [[system-spec-service-worker-stub#Why a leftover real service worker is cleared before the stub goes in]]
  def go_slow_link!
    set_network_conditions(
      offline: false,
      latency: SLOW_LINK_LATENCY_MS,
      download_throughput: SLOW_LINK_DOWNLOAD_BYTES_PER_SECOND,
      upload_throughput: SLOW_LINK_UPLOAD_BYTES_PER_SECOND
    )
  end

  private

  def set_network_conditions(offline:, latency: 0, download_throughput: 0, upload_throughput: 0)
    browser = page.driver.browser
    if browser.respond_to?(:network_conditions=)
      browser.network_conditions = {
        offline: offline,
        latency: latency,
        download_throughput: download_throughput,
        upload_throughput: upload_throughput
      }
    else
      browser.execute_cdp(
        "Network.emulateNetworkConditions",
        offline: offline,
        latency: latency,
        downloadThroughput: download_throughput,
        uploadThroughput: upload_throughput
      )
    end
  end
end

RSpec.configure do |config|
  config.include ServiceWorkerStub, type: :system

  # @lat: [[system-spec-service-worker-stub#Why a leftover real service worker is cleared before the stub goes in]]
  config.after(:each, type: :system) do
    clear_service_worker_stub! if respond_to?(:clear_service_worker_stub!)
  end
end
