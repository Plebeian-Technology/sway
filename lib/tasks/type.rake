desc "Run RBS and Steep type checking"
task :type do
  next if system("bundle exec rbs validate") && system("bundle exec steep check")

  abort("Type checking failed")
end
