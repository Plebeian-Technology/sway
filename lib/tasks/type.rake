# typed: false

desc "Run Sorbet type checking"
task :type do
  next if system("bundle exec srb tc")

  abort("Sorbet type checking failed")
end
