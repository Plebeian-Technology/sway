# typed: true

# DO NOT EDIT MANUALLY
# This is an autogenerated file for types exported from the `debug_inspector` gem.
# Please instead update this file by running `bin/tapioca gem debug_inspector`.


# source://debug_inspector//lib/debug_inspector/version.rb#1
class DebugInspector
  def backtrace_locations; end
  def frame_binding(_arg0); end
  def frame_class(_arg0); end
  def frame_iseq(_arg0); end
  def frame_self(_arg0); end

  class << self
    def open; end
  end
end

# Don't forget to update the version string in the gemspec file.
#
# source://debug_inspector//lib/debug_inspector/version.rb#3
DebugInspector::VERSION = T.let(T.unsafe(nil), String)

# source://debug_inspector//lib/debug_inspector.rb#20
RubyVM::DebugInspector = DebugInspector