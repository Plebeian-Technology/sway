# frozen_string_literal: true

module PdfSubprocessRunner
  private

  def run_subprocess_translated(
    *command,
    label: nil,
    target: nil,
    error_class: self.class::ExtractionFailed,
    &block
  )
    label ||= command.first
    stdout, stderr, status = Sway::Subprocess.capture3(*command)
    unless status.success?
      err_class = block ? block.call(Sway::Utf8.scrub(stderr), :failed) : error_class
      raise err_class, "#{label} failed#{target}: #{Sway::Utf8.scrub(stderr)[0, 500]}"
    end
    Sway::Utf8.scrub(stdout)
  rescue Sway::Subprocess::TimedOut => e
    raise error_class, "#{label} timed out#{target}: #{e.message.to_s[0, 200]}"
  rescue Sway::Subprocess::OutputTooLarge => e
    err_class = block ? block.call(e.stderr, :output_too_large) : error_class
    raise err_class, "#{label} output too large#{target}: #{e.message.to_s[0, 200]}"
  rescue SystemCallError => e
    raise error_class, "#{label} unavailable: #{e.class.name.demodulize}: #{e.message.to_s[0, 200]}"
  end
end
