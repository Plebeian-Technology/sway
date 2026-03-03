repo_path ".gem_rbs_collection"

target :app do
  signature "sig"

  collection_config "rbs_collection.yaml"

  check "app"
  check "lib"

  ignore "db/schema.rb"
  ignore "db/migrate"
  ignore "bin"
  ignore "log"
  ignore "node_modules"
  ignore "tmp"
  ignore "vendor"
end

target :test do
  signature "sig"
  signature "sig-test"

  collection_config "rbs_collection.yaml"

  check "spec"
  ignore "spec/screenshots"
end
