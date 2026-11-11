# frozen_string_literal: true

# @lat: [[verification-gates#The frontend test bundle a spec run reads]]
RailsVite.config.build_dir = ENV["SWAY_VITE_BUILD_DIR"] if ENV["SWAY_VITE_BUILD_DIR"].present?
RailsVite.config.auto_build = false if Rails.env.test?
