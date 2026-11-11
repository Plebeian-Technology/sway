# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::AtomicWrite do
  around do |example|
    Dir.mktmpdir do |dir|
      @atomic_write_dir = Pathname(dir)
      example.run
    end
  end

  def atomic_write_dest
    @atomic_write_dir.join("artifact.txt")
  end

  def atomic_write_tmp_siblings
    @atomic_write_dir.children.reject { |child| child == atomic_write_dest }
  end

  it "leaves the destination holding the written content" do
    described_class.write(atomic_write_dest) { |tmp_path| tmp_path.write("hello") }

    expect(atomic_write_dest.read).to eq("hello")
  end

  it "renames a same-directory temp file into place rather than writing the destination directly" do
    seen_tmp_path = nil #: Pathname?

    expect(File).to receive(:rename).and_wrap_original do |original, from, to|
      tmp_path = Pathname(from)
      seen_tmp_path = tmp_path
      expect(tmp_path.dirname).to eq(atomic_write_dest.dirname)
      expect(atomic_write_dest.exist?).to be false
      original.call(from, to)
    end

    described_class.write(atomic_write_dest) { |tmp_path| tmp_path.write("hello") }

    expect(seen_tmp_path).not_to be_nil
    expect(atomic_write_tmp_siblings).to be_empty
  end

  it "does not leave a temp file behind when the write block fails" do
    expect {
      described_class.write(atomic_write_dest) { raise Errno::ENOSPC, "No space left on device" }
    }.to raise_error(Errno::ENOSPC)

    expect(atomic_write_dest.exist?).to be false
    expect(atomic_write_tmp_siblings).to be_empty
  end

  it "does not leave a temp file behind when the rename fails" do
    allow(File).to receive(:rename).and_raise(Errno::EROFS, "Read-only file system")

    expect {
      described_class.write(atomic_write_dest) { |tmp_path| tmp_path.write("hello") }
    }.to raise_error(Errno::EROFS)

    expect(atomic_write_dest.exist?).to be false
    expect(atomic_write_tmp_siblings).to be_empty
  end
end
