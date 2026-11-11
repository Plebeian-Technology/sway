# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

# @lat: [[testing-the-toolchain#A script is proved by running it]]
RSpec.describe "scripts/uncommitted_digest.sh" do
  it "answers nothing for a clean tree and a stable fingerprint for a dirty one" do
    script = Rails.root.join("scripts", "uncommitted_digest.sh").to_s

    run_in = lambda do |dir|
      out, _err, status = Open3.capture3(script, chdir: dir)
      raise "script failed in #{dir}" unless status.success?

      out.strip
    end

    Dir.mktmpdir do |dir|
      %w[init -q].then { |args| Open3.capture3("git", *args, chdir: dir) }
      Open3.capture3("git", "config", "user.email", "t@example.com", chdir: dir)
      Open3.capture3("git", "config", "user.name", "T", chdir: dir)
      File.write(File.join(dir, "a.txt"), "one\n")
      Open3.capture3("git", "add", ".", chdir: dir)
      Open3.capture3("git", "commit", "-qm", "first", chdir: dir)

      expect(run_in.call(dir)).to eq("")

      File.write(File.join(dir, "a.txt"), "two\n")
      dirty = run_in.call(dir)
      expect(dirty).to match(/\A[0-9a-f]{8}\z/)

      # Same tree, same answer, or two reads of one page would disagree.
      expect(run_in.call(dir)).to eq(dirty)

      File.write(File.join(dir, "a.txt"), "three\n")
      expect(run_in.call(dir)).not_to eq(dirty)
    end
  end

  # Pins the limit the comments describe, so the description stays true.
  it "cannot tell two trees apart by the contents of an untracked file" do
    script = Rails.root.join("scripts", "uncommitted_digest.sh").to_s

    digest_with_untracked_body = lambda do |body|
      Dir.mktmpdir do |dir|
        Open3.capture3("git", "init", "-q", chdir: dir)
        Open3.capture3("git", "config", "user.email", "t@example.com", chdir: dir)
        Open3.capture3("git", "config", "user.name", "T", chdir: dir)
        File.write(File.join(dir, "a.txt"), "one\n")
        Open3.capture3("git", "add", ".", chdir: dir)
        Open3.capture3("git", "commit", "-qm", "first", chdir: dir)
        File.write(File.join(dir, "new.txt"), body)
        out, _err, _status = Open3.capture3(script, chdir: dir)
        out.strip
      end
    end

    expect(digest_with_untracked_body.call("aaa\n")).to eq(digest_with_untracked_body.call("bbb\n"))
  end

  # @lat: [[system-shape#Deployment#The release fingerprint never runs a diff converter]]
  it "still answers when a gitattributes textconv driver fails" do
    script = Rails.root.join("scripts", "uncommitted_digest.sh").to_s

    Dir.mktmpdir do |dir|
      Open3.capture3("git", "init", "-q", chdir: dir)
      Open3.capture3("git", "config", "user.email", "t@example.com", chdir: dir)
      Open3.capture3("git", "config", "user.name", "T", chdir: dir)
      File.write(File.join(dir, "secret.enc"), "one\n")
      File.write(File.join(dir, ".gitattributes"), "secret.enc diff=boom\n")
      Open3.capture3("git", "add", ".", chdir: dir)
      Open3.capture3("git", "commit", "-qm", "first", chdir: dir)
      Open3.capture3("git", "config", "diff.boom.textconv", "false", chdir: dir)

      File.write(File.join(dir, "secret.enc"), "two\n")

      out, err, status = Open3.capture3(script, chdir: dir)

      expect(status).to be_success, "script exited #{status.exitstatus}: #{err}"
      expect(out.strip).to match(/\A[0-9a-f]{8}\z/)
    end
  end
end
