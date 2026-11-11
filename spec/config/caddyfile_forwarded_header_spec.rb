# frozen_string_literal: true

require "spec_helper"

RSpec.describe ".dockerdev/Caddyfile Forwarded header stripping" do
  it "strips the untrusted Forwarded header inside the upstream reverse_proxy block" do
    caddyfile_content = File.read(File.expand_path("../../.dockerdev/Caddyfile", __dir__.to_s))
    upstream_block = caddyfile_content[/reverse_proxy\s+\{\$APP_UPSTREAM\}\s*\{([^}]*)\}/m, 1]

    expect(upstream_block).not_to be_nil,
      "expected reverse_proxy {$APP_UPSTREAM} to have a block in .dockerdev/Caddyfile"
    expect(upstream_block).to match(/^\s*header_up\s+-Forwarded\b/)
  end
end
