---
lat:
  mode: explanation
---

# Stub the HTTP layer, not Faraday.get

`SwayRegistrationService#find_legislators_from_open_states_geo_endpoint` calls openstates.org through `Sway::FaradayStack.open_states.get`, an instance method on a connection object — not the `Faraday.get` class method.

A spec that stubs `allow(Faraday).to receive(:get)` never catches that call, and the real request escapes to VCR as an unhandled call. Specs that need to fake this request use WebMock (`stub_request`) to stub the HTTP layer itself instead, which also survives the next time the calling code moves to a different Faraday API.

## The stub is only reachable when the API key is set

`#find_legislators_from_open_states_geo_endpoint` returns `[]` immediately when `ENV["OPEN_STATES_API_KEY"]` is blank, before making any HTTP call at all.

`.env*` files are not checked into git, so whether a `stub_request` in this area did anything used to depend on the developer's machine. Specs that exercise this path set the key explicitly with `stub_const("ENV", ENV.to_h.merge("OPEN_STATES_API_KEY" => "test-open-states-key"))`, the same way `maryland_refresh_spec.rb` does, so the stub is exercised the same way on every machine and in CI.

`spec/system/user_registration_spec.rb` sets the key with an `ENV[...] =` override in its `around` block for the same reason: without a key the fake OpenStates responses it stubs are never reached, so a statewide example asserting on OpenStates resolution would exercise an empty short-circuit instead of the HTTP boundary.
