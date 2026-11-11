#!/usr/bin/env ruby
# frozen_string_literal: true

# @lat: [[publish-the-github-wiki]]
require_relative "github_wiki_builder"

output_dir = ARGV[0]
if output_dir.nil? || output_dir.strip.empty?
  warn "usage: scripts/build-github-wiki.rb <output-dir> [repo-slug] [branch]"
  exit 1
end

arg_repo = ARGV[1].to_s.strip
arg_branch = ARGV[2].to_s.strip
repo = arg_repo.empty? ? Sway::GitHubWikiBuilder::DEFAULT_REPO : arg_repo
branch = arg_branch.empty? ? Sway::GitHubWikiBuilder::DEFAULT_BRANCH : arg_branch
root = File.expand_path("..", __dir__)

builder = Sway::GitHubWikiBuilder.new(root, repo: repo, branch: branch)
written = builder.build(output_dir)
puts "[build-github-wiki] wrote #{written.size} pages to #{File.expand_path(output_dir)} (repo=#{repo}, branch=#{branch})"
