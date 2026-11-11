# frozen_string_literal: true

# @lat: [[comments-and-docs#The legacy docs index and its generator]]
namespace :sway do
  namespace :docs do
    desc "Rebuild docs/index.md from every doc's frontmatter"
    task :index do
      require_relative "../sway/docs_index"

      index = Sway::DocsIndex.new(File.expand_path("../..", __dir__))
      changed = index.write
      puts changed ? "[sway:docs:index] rewrote #{index.path}" : "[sway:docs:index] #{index.path} was already current"
    end
  end
end
