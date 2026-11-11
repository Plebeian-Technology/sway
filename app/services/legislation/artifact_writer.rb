# frozen_string_literal: true

module Legislation
  class ArtifactWriter
    def self.write(path, content, stage:, atomic: true)
      path = Pathname.new(path)
      path.dirname.mkpath

      if atomic
        Legislation::AtomicWrite.write(path) { |tmp_path| tmp_path.write(content) }
      else
        File.write(path, content)
      end
    rescue SystemCallError, IOError => e
      raise BillProcessingError,
        "#{stage}: artifact write failed: #{e.class.name.demodulize}: #{e.message.to_s[0, 200]}"
    end
  end
end
