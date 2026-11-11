# frozen_string_literal: true

# @lat: [[object-spec-methods-universal-name-policy#Known gap: names already in the shim before this guard existed]]
# Widening the forbidden list below is always right; narrowing it is not.
shim_path = File.expand_path("../../sig-test/object_spec_methods.rbs", __dir__.to_s)

# @lat: [[object-spec-methods-universal-name-policy#Why call is listed first, and why the list is local variables, not constants]]
forbidden_universal_names = %w[
  call result perform execute value data id to_s each map
  subject response error message
]

RSpec.describe "sig-test/object_spec_methods.rbs universal-name policy" do
  forbidden_universal_names.each do |method_name|
    it "does not declare `#{method_name}` on Object" do
      # Read the file inline rather than through a `let`: a `let` would need its
      # own name declared on Object, in the very file this example polices.
      expect(File.read(shim_path)).not_to match(/^\s*def #{Regexp.escape(method_name)}:/),
        "sig-test/object_spec_methods.rbs declares `def #{method_name}:` on Object, which " \
        "erases type checking for every `.#{method_name}` in the :test target. Give the spec " \
        "helper a prefixed name (e.g. subject(:citation_result)) and declare that instead."
    end
  end
end
