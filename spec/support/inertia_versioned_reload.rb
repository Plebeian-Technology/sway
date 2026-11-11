# frozen_string_literal: true

# @lat: [[inertia-reload-only-helper-version-header-gap#Why some partial-reload specs build the request by hand]]
module InertiaVersionedReload
  def inertia_versioned_reload_only(*props)
    get request.fullpath, headers: {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
      "X-Inertia-Partial-Data" => props.join(","),
      "X-Inertia-Partial-Component" => inertia.component
    }
  end
end

RSpec.configure do |config|
  config.include InertiaVersionedReload, type: :request
end
