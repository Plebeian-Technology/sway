# frozen_string_literal: true

# @lat: [[sqlite-integrity-check-boot-hook#Why the integrity check initializer is a thin hook]]
require Rails.root.join("lib", "sqlite_integrity_check")

Rails.application.config.after_initialize do
  next unless Sway::BootEnqueue.web_server_process?

  SqliteIntegrityCheck.run(env: Rails.env)
end
