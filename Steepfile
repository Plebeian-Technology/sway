repo_path ".gem_rbs_collection"

target :app do
  signature "sig"

  collection_config "rbs_collection.yaml"

  library "open-uri"
  # WS1.12: ExternalAssetMirrorService resolves upstream hosts and classifies
  # their addresses to reject private/loopback/link-local SSRF targets.
  library "resolv"
  library "ipaddr"
  # Sway::DocsIndex reads YAML header blocks with Psych.
  library "psych"

  check "app"
  check "lib"

  # @lat: [[rbs-signatures#Why the lint tooling is left out of the check]]
  ignore "lib/assets"
  ignore "lib/cops"
  ignore "app/assets"
  ignore "app/frontend"
  ignore "app/helpers"
  ignore "app/views"

  # Sway: suppress two diagnostics project-wide (chosen over per-literal
  # annotations). UnannotatedEmptyCollection fires on bare [] / {} whose
  # element type is obvious from context; UnknownInstanceVariable is noisy
  # against Rails' dynamically-assigned ivars. Severity nil = not reported.
  # Base hash is Diagnostic::Ruby.default.dup, so all other diagnostics keep
  # their default severity.
  configure_code_diagnostics do |hash|
    hash[Steep::Diagnostic::Ruby::UnannotatedEmptyCollection] = nil
    hash[Steep::Diagnostic::Ruby::UnknownInstanceVariable] = nil
  end
end

target :test do
  signature "sig"
  signature "sig-test"

  collection_config "rbs_collection.yaml"

  library "open-uri"
  library "psych"
  library "shellwords"

  check "spec"
  ignore "spec/screenshots"
  # @lat: [[rbs-signatures#Why the lint tooling is left out of the check]]
  ignore "spec/cops"

  # Sway: same project-wide suppressions as the :app target (see the comment
  # there). Base hash is Diagnostic::Ruby.default.dup; only these two change.
  configure_code_diagnostics do |hash|
    hash[Steep::Diagnostic::Ruby::UnannotatedEmptyCollection] = nil
    hash[Steep::Diagnostic::Ruby::UnknownInstanceVariable] = nil
  end
end
