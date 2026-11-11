# frozen_string_literal: true

module Legislation
  # @lat: [[legislation-pipeline#Artifacts are files, not rows#Every artifact write replaces the file in one step]]
  module AtomicWrite
    def self.write(path)
      path = Pathname(path)
      tmp_path = path.dirname.join(".#{path.basename}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}")
      yield tmp_path
      File.rename(tmp_path, path)
      path
    rescue SystemCallError, IOError
      tmp_path.delete if tmp_path&.exist?
      raise
    end
  end
end
