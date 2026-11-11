desc "Run RBS validation, then steep type checking"
task :type do
  # @lat: [[rbs-signatures#Why this is not caught by the verification gate]]
  next if system("bundle exec rbs -I sig -I sig-test validate") && system("bin/steep check --severity-level=information")

  abort("Type checking failed")
end
