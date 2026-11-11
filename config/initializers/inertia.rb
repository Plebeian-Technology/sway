# frozen_string_literal: true

InertiaRails.configure do |config|
  config.ssr_enabled = false

  config.use_script_element_for_initial_page = true
  config.use_data_inertia_head_attribute = true
  config.always_include_errors_hash = true
  # @lat: [[inertia-initializer-config#config.encrypt_history: why page data is encrypted before it's stored]]
  config.version = RailsVite.digest
  config.encrypt_history = true
end
