# frozen_string_literal: true

# @lat: [[page-reload-probe-design#Why plant_reload_probe! checks its own mark before returning]]
module PageReloadProbe
  PROBE_EXPRESSION = "window.__swayReloadProbe"
  PROBE_VALUE = "planted"

  # @lat: [[page-reload-probe-design#Why plant_reload_probe! checks its own mark before returning]]
  def plant_reload_probe!
    page.execute_script("#{PROBE_EXPRESSION} = '#{PROBE_VALUE}';")
    raise "reload probe did not take" unless
      page.evaluate_script(PROBE_EXPRESSION) == PROBE_VALUE
  end

  # Read the mark back. Still there means this is the same document it was
  # planted on.
  def expect_no_full_page_load!
    expect(page.evaluate_script(PROBE_EXPRESSION)).to eq(PROBE_VALUE)
  end
end

RSpec.configure { |config| config.include PageReloadProbe, type: :system }
