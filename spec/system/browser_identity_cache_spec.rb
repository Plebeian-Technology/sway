# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Browser identity cache isolation", type: :system, js: true do
  around do |example|
    previous_host = Capybara.server_host
    previous_app_host = Capybara.app_host
    previous_port = Capybara.always_include_port
    begin
      Capybara.server_host = "localhost"
      Capybara.app_host = "http://localhost"
      Capybara.always_include_port = true
      example.run
    ensure
      Capybara.server_host = previous_host
      Capybara.app_host = previous_app_host
      Capybara.always_include_port = previous_port
    end
  end

  # @lat: [[client-caches-and-identity#Browser upgrade regression]]
  it "replaces a legacy worker without serving an earlier account under slow or offline networking" do
    create(:sway_locale, :baltimore)
    first_user = create(:user)
    second_user = create(:user)
    [first_user, second_user].each do |user|
      complete_registration_with_active_link(user)
    end

    build_dir = RailsVite.config.build_dir
    unique = "identity-cache-#{SecureRandom.hex(8)}"
    fixture_path = Rails.public_path.join(build_dir, "#{unique}.html")
    worker_path = Rails.public_path.join(build_dir, "#{unique}.js")
    compiled_worker = Rails.public_path.join(build_dir, "sw.js").read
    begin
      File.write(fixture_path, "<!doctype html><title>Worker identity regression</title>")
      File.write(worker_path, <<~JS)
        self.addEventListener("install", event => event.waitUntil(self.skipWaiting()));
        self.addEventListener("activate", event => event.waitUntil(self.clients.claim()));
        self.addEventListener("fetch", event => {
          if (new URL(event.request.url).pathname !== "/legislators") return;
          const name = event.request.headers.get("X-Inertia") === "true" ? "inertia-pages" : "inertia-navigations";
          event.respondWith(caches.open(name).then(cache => cache.match(event.request.url)).then(cached => cached || fetch(event.request)));
        });
      JS

      visit "/#{build_dir}/#{unique}.html"
      browser = page.driver.browser
      begin
        browser.execute_cdp("Network.enable")
        browser.execute_cdp("Network.setCacheDisabled", cacheDisabled: true)
        browser.manage.delete_all_cookies
        expect(browser_json_request("POST", "/test/sessions", {user_id: first_user.id}).fetch("status")).to eq(200)

        seeded = browser.execute_async_script(<<~JS, "/#{build_dir}/#{unique}.js", "/#{build_dir}/")
          const [script, scope, done] = arguments;
          (async () => {
            await Promise.all((await navigator.serviceWorker.getRegistrations()).map(reg => reg.unregister()));
            await Promise.all((await caches.keys()).map(name => caches.delete(name)));
            const html = await (await fetch("/legislators", {cache: "no-store"})).text();
            const root = new DOMParser().parseFromString(html, "text/html").querySelector('script[data-page="app"][type="application/json"]');
            window.identityPageVersion = JSON.parse(root.textContent).version;
            const response = await fetch("/legislators", {headers: {"X-Inertia": "true", "X-Inertia-Version": window.identityPageVersion, "Accept": "text/html"}, cache: "no-store"});
            const body = await response.clone().json();
            await (await caches.open("inertia-pages")).put(location.origin + "/legislators", response);
            await (await caches.open("inertia-navigations")).put(location.origin + "/legislators", new Response("OLD_IDENTITY_HTML", {headers: {"Content-Type": "text/html"}}));
            await navigator.serviceWorker.register(script, {scope, updateViaCache: "none"});
            await navigator.serviceWorker.ready;
            await new Promise((resolve, reject) => {
              if (navigator.serviceWorker.controller) return resolve();
              navigator.serviceWorker.addEventListener("controllerchange", resolve, {once: true});
              setTimeout(() => reject(new Error("Legacy worker did not control fixture")), 10000);
            });
            done({userId: body.props.user.id});
          })().catch(error => done({failure: String(error)}));
        JS
        expect(seeded).to eq("userId" => first_user.id)

        expect(browser_json_request("POST", "/test/sessions", {user_id: second_user.id}).fetch("status")).to eq(200)
        expect(identity_worker_fetch).to include("userId" => first_user.id)

        legacy_modified_at = File.mtime(worker_path)
        File.write(worker_path, compiled_worker)
        File.utime(legacy_modified_at + 2, legacy_modified_at + 2, worker_path)
        upgraded = browser.execute_async_script(<<~JS)
          const done = arguments[arguments.length - 1];
          const states = [];
          let registration;
          let servedNewWorker = false;
          (async () => {
            registration = await navigator.serviceWorker.getRegistration();
            const served = await (await fetch(registration.active.scriptURL, {cache: "no-store"})).text();
            servedNewWorker = served.includes("DYNAMIC_PAGES_NETWORK_ONLY");
            registration.addEventListener("updatefound", () => {
              const installing = registration.installing;
              states.push(installing.state);
              installing.addEventListener("statechange", () => states.push(installing.state));
            });
            const controlled = new Promise((resolve, reject) => {
              navigator.serviceWorker.addEventListener("controllerchange", resolve, {once: true});
              setTimeout(() => reject(new Error("Upgraded worker did not take control")), 15000);
            });
            await registration.update();
            await controlled;
            await new Promise((resolve, reject) => {
              const active = registration.active;
              if (active.state === "activated") return resolve();
              active.addEventListener("statechange", () => {
                if (active.state === "activated") resolve();
                if (active.state === "redundant") reject(new Error("Replacement worker became redundant"));
              });
              setTimeout(() => reject(new Error("Replacement activation did not finish")), 10000);
            });
            const channel = new MessageChannel();
            const acknowledged = new Promise((resolve, reject) => {
              channel.port1.onmessage = event => resolve(event.data);
              setTimeout(() => reject(new Error("Worker did not acknowledge network-only policy")), 5000);
            });
            navigator.serviceWorker.controller.postMessage({type: "DYNAMIC_PAGES_NETWORK_ONLY"}, [channel.port2]);
            done({acknowledgement: await acknowledged, caches: await caches.keys(),
              scriptURL: navigator.serviceWorker.controller.scriptURL, state: navigator.serviceWorker.controller.state});
          })().catch(error => done({failure: String(error), states, servedNewWorker,
            installing: registration?.installing?.state, waiting: registration?.waiting?.state,
            active: registration?.active?.state}));
        JS
        expect(upgraded["failure"]).to be_nil, upgraded.inspect
        expect(upgraded["acknowledgement"]).to eq("success" => true)
        expect(upgraded.fetch("caches")).not_to include("inertia-pages", "inertia-navigations"), upgraded.inspect
        expect(upgraded.fetch("state")).to eq("activated")

        browser.execute_cdp("Network.emulateNetworkConditions", offline: false, latency: 150, downloadThroughput: 250_000, uploadThroughput: 250_000)
        expect(identity_worker_fetch).to include("userId" => second_user.id)

        browser.execute_cdp("Network.emulateNetworkConditions", offline: true, latency: 0, downloadThroughput: 0, uploadThroughput: 0)
        expect(identity_worker_fetch).to include("networkError" => true)
        offline = browser.execute_async_script(<<~JS)
          const done = arguments[arguments.length - 1];
          (async () => {
            const cacheName = (await caches.keys()).find(name => name.includes("precache"));
            if (!cacheName) throw new Error("Static precache was not installed");
            const requests = await (await caches.open(cacheName)).keys();
            const asset = requests.find(request => new URL(request.url).pathname.endsWith(".js"));
            if (!asset) throw new Error("Static script missing from precache");
            const assetURL = new URL(asset.url);
            assetURL.searchParams.delete("__WB_REVISION__");
            const staticResponse = await fetch(assetURL, {cache: "no-store"});
            let dynamicUnavailable = false;
            try { await fetch("/legislators", {headers: {"Accept": "text/html"}, cache: "no-store"}); }
            catch { dynamicUnavailable = true; }
            done({staticStatus: staticResponse.status, dynamicUnavailable});
          })().catch(error => done({failure: String(error)}));
        JS
        expect(offline).to eq("staticStatus" => 200, "dynamicUnavailable" => true)
      ensure
        browser.execute_cdp("Network.emulateNetworkConditions", offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1)
        browser.execute_cdp("Network.setCacheDisabled", cacheDisabled: false)
        browser.execute_async_script(<<~JS)
          const done = arguments[arguments.length - 1];
          Promise.all([
            navigator.serviceWorker.getRegistrations().then(regs => Promise.all(regs.map(reg => reg.unregister()))),
            caches.keys().then(names => Promise.all(names.map(name => caches.delete(name))))
          ]).then(() => done(true), () => done(false));
        JS
      end
    ensure
      FileUtils.rm_f(fixture_path)
      FileUtils.rm_f(worker_path)
    end
  end

  def identity_worker_fetch
    page.driver.browser.execute_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      fetch("/legislators", {headers: {"X-Inertia": "true", "X-Inertia-Version": window.identityPageVersion, "Accept": "text/html"}, cache: "no-store"})
        .then(response => response.json()).then(body => done({userId: body.props.user.id}))
        .catch(() => done({networkError: true}));
    JS
  end
end
