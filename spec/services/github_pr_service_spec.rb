# frozen_string_literal: true

require "rails_helper"

# Unit coverage for GitHubPrService. Every Octokit call is stubbed.
# instance_double covers Octokit::Client; small Structs stand in for its
# return objects (no OpenStruct in Ruby 4.0).

# Small stand-ins for the objects Octokit returns (OpenStruct is not in Ruby
# 4.0's standard library)
GHRepo = Struct.new(:default_branch)
GHObject = Struct.new(:sha)
GHRef = Struct.new(:object)
GHTree = Struct.new(:sha)
# @lat: [[testing-the-toolchain#A stand-in has to have the shape the real object has]]
GHCommitDetail = Struct.new(:tree) # .tree.sha
GHCommit = Struct.new(:sha, :commit) # @client.commit (repo commits endpoint): .commit.tree.sha
# @client.create_commit (git data endpoint): flat .tree.sha, no .commit.
GHGitCommit = Struct.new(:sha, :tree)
GHPR = Struct.new(:number, :html_url)

RSpec.describe GitHubPrService do
  # Stands in for the real token, so tests need no GitHub credential
  let(:fake_token) { "ghp_test_token_#{SecureRandom.hex(4)}" }

  # Test double for Octokit::Client
  let(:octokit_client) { instance_double(Octokit::Client) }

  # Repository name resolved from git config
  let(:repo_name) { "Plebeian-Technology/sway" }

  # @lat: [[testing-the-toolchain#A stub has to name the seam the caller uses]]
  def stub_git_remote(&answer)
    allow(Sway::Subprocess).to receive(:capture3)
      .with("git", "config", "--get", "remote.origin.url", timeout_seconds: GitHubPrService::GIT_TIMEOUT_SECONDS, &answer)
  end

  before do
    allow(EnvSecret).to receive(:fetch!).with("GITHUB_TOKEN").and_return(fake_token)
    # Resolve the repo from the environment by default, so tests need no .git dir
    allow(EnvSecret).to receive(:read).with("GITHUB_REPO").and_return(repo_name)
    stub_git_remote { ["https://github.com/#{repo_name}.git\n", "", instance_double(Process::Status, success?: true)] }
    allow(Octokit::Client).to receive(:new).with(access_token: fake_token).and_return(octokit_client)
  end

  # -------------------------------------------------------------------
  # Shared doubles for "ref / commit / branch" API responses
  # -------------------------------------------------------------------
  let(:base_commit_sha) { "abc123base" }
  let(:base_tree_sha) { "tree_sha_of_base" }
  let(:default_branch_name) { "main" }

  let(:repo_double) { GHRepo.new(default_branch_name) }
  let(:base_ref_double) { GHRef.new(GHObject.new(base_commit_sha)) }

  # Returns a fake @client.commit response with .commit.tree.sha
  def make_commit(sha, tree_sha)
    GHCommit.new(sha, GHCommitDetail.new(GHTree.new(tree_sha)))
  end

  # Returns a fake @client.create_commit response with .tree.sha, no .commit
  def make_git_commit(sha, tree_sha)
    GHGitCommit.new(sha, GHTree.new(tree_sha))
  end

  # -------------------------------------------------------------------
  # (a) Empty files => nil, no API calls
  # -------------------------------------------------------------------
  describe "#open_pr with empty files" do
    it "returns nil immediately without making any Octokit API calls" do
      service = described_class.new(token: fake_token)

      # Expect NO Octokit calls. Nothing is stubbed, so instance_double raises
      # if any unexpected method is called.
      expect(octokit_client).not_to receive(:ref)
      expect(octokit_client).not_to receive(:create_ref)
      expect(octokit_client).not_to receive(:create_pull_request)

      result = service.open_pr(branch: "seeds/test", title: "T", body: "B", files: {})

      expect(result).to be_nil
    end
  end

  describe "#open_pr with a single file" do
    let(:blob_sha) { "blob_sha_file1" }
    let(:tree_sha_1) { "tree_sha_after_file1" }
    let(:commit_sha_1) { "commit_sha_file1" }
    let(:file_tree_sha_1) { "file_tree_sha_1" } # the new commit's tree sha

    let(:pr_double) { GHPR.new(42, "https://github.com/#{repo_name}/pull/42") }

    before do
      allow(octokit_client).to receive(:repo).with(repo_name).and_return(repo_double)
      allow(octokit_client).to receive(:ref).with(repo_name, "heads/#{default_branch_name}")
        .and_return(base_ref_double)
      allow(octokit_client).to receive(:commit).with(repo_name, base_commit_sha)
        .and_return(make_commit(base_commit_sha, base_tree_sha))
      allow(octokit_client).to receive(:create_ref).and_return(nil)
      allow(octokit_client).to receive(:create_blob).and_return(blob_sha)
      allow(octokit_client).to receive(:create_tree).and_return(GHTree.new(tree_sha_1))
      allow(octokit_client).to receive(:create_commit)
        .and_return(make_git_commit(commit_sha_1, file_tree_sha_1))
      allow(octokit_client).to receive(:update_ref).and_return(nil)
      allow(octokit_client).to receive(:create_pull_request).and_return(pr_double)
    end

    it "creates exactly one pull request" do
      service = described_class.new(token: fake_token)
      branch = "seeds/refresh-legislators-20260605"
      files = {"db/seeds/data/congress/legislators.json" => '{"members":[]}'}

      result = service.open_pr(branch: branch, title: "Refresh", body: "auto", files: files)

      expect(result).to eq(pr_double)
      expect(octokit_client).to have_received(:create_pull_request).once
    end
  end

  describe "#open_pr with branch collision" do
    # Build an Octokit::UnprocessableEntity using allocate to bypass the
    # Faraday::Response constructor requirement.
    let(:collision_error) { Octokit::UnprocessableEntity.allocate }

    before do
      allow(octokit_client).to receive(:repo).with(repo_name).and_return(repo_double)
      allow(octokit_client).to receive(:ref).with(repo_name, "heads/#{default_branch_name}")
        .and_return(base_ref_double)
      allow(octokit_client).to receive(:commit).with(repo_name, base_commit_sha)
        .and_return(make_commit(base_commit_sha, base_tree_sha))
      allow(octokit_client).to receive(:create_ref).and_raise(collision_error)
    end

    it "logs a warning and re-raises Octokit::UnprocessableEntity" do
      service = described_class.new(token: fake_token)

      expect(SwayLogging).to receive(:log_exception).with("github_pr.branch_conflict", exception: anything, branch: anything, level: :warn)

      expect do
        service.open_pr(
          branch: "seeds/refresh-legislators-20260605",
          title: "T", body: "B",
          files: {"path/to/file.json" => "{}"}
        )
      end.to raise_error(Octokit::UnprocessableEntity)
    end
  end

  describe "#open_pr L5: base_tree is a TREE sha (not the commit sha)" do
    let(:commit_1_sha) { "commit_sha_for_file1" }
    let(:commit_1_tree_sha) { "tree_sha_for_commit1" }
    let(:commit_2_sha) { "commit_sha_for_file2" }
    let(:commit_2_tree_sha) { "tree_sha_for_commit2" }

    let(:pr_double) { GHPR.new(43, nil) }

    # Track what base_tree was passed to each create_tree call
    let(:create_tree_calls) { [] } #: Array[Hash[Symbol, untyped]]

    before do
      allow(octokit_client).to receive(:repo).with(repo_name).and_return(repo_double)
      allow(octokit_client).to receive(:ref).with(repo_name, "heads/#{default_branch_name}")
        .and_return(base_ref_double)
      # The initial commit lookup returns base_tree_sha (a TREE sha, different from base_commit_sha)
      allow(octokit_client).to receive(:commit).with(repo_name, base_commit_sha)
        .and_return(make_commit(base_commit_sha, base_tree_sha))
      allow(octokit_client).to receive(:create_ref).and_return(nil)
      allow(octokit_client).to receive(:create_blob).and_return("blob_sha")

      call_count = 0
      allow(octokit_client).to receive(:create_tree) do |_repo, _entries, **kwargs|
        create_tree_calls << {base_tree: kwargs[:base_tree]}
        tree_sha = call_count.zero? ? "tree_after_file1" : "tree_after_file2"
        call_count += 1
        GHTree.new(tree_sha)
      end

      commit_count = 0
      allow(octokit_client).to receive(:create_commit) do |*|
        if commit_count.zero?
          commit_count += 1
          make_git_commit(commit_1_sha, commit_1_tree_sha)
        else
          make_git_commit(commit_2_sha, commit_2_tree_sha)
        end
      end

      allow(octokit_client).to receive(:update_ref).and_return(nil)
      allow(octokit_client).to receive(:create_pull_request).and_return(pr_double)
    end

    it "passes the base commit's TREE sha (not base_commit_sha) as base_tree for the first file" do
      service = described_class.new(token: fake_token)
      files = {
        "path/file1.json" => '{"a":1}',
        "path/file2.json" => '{"b":2}'
      }

      service.open_pr(branch: "seeds/test-l5", title: "T", body: "B", files: files)

      # First file: base_tree must be the TREE sha from the base commit, NOT base_commit_sha
      expect(create_tree_calls[0][:base_tree]).to eq(base_tree_sha)
      expect(create_tree_calls[0][:base_tree]).not_to eq(base_commit_sha)
    end

    it "passes the first commit's TREE sha as base_tree for the second file" do
      service = described_class.new(token: fake_token)
      files = {
        "path/file1.json" => '{"a":1}',
        "path/file2.json" => '{"b":2}'
      }

      service.open_pr(branch: "seeds/test-l5", title: "T", body: "B", files: files)

      # Second file: base_tree must be commit_1_tree_sha (the tree sha of commit 1)
      expect(create_tree_calls[1][:base_tree]).to eq(commit_1_tree_sha)
      expect(create_tree_calls[1][:base_tree]).not_to eq(commit_1_sha)
    end
  end

  # @repo resolution: environment (GITHUB_REPO) first, git remote as fallback.
  describe "CR-02: @repo resolution" do
    context "when GITHUB_REPO env var is set" do
      before do
        # Replace the git-remote stub so we can prove it is NOT called
        stub_git_remote { raise "git config should not be called when GITHUB_REPO is set" }
        # The GITHUB_TOKEN lookup is already stubbed in the outer before block.
        # Add the GITHUB_REPO stub.
        allow(EnvSecret).to receive(:read).with("GITHUB_REPO").and_return("owner/sway-repo")
        allow(EnvSecret).to receive(:fetch!).with("GITHUB_TOKEN").and_return(fake_token)
      end

      it "uses the env var value as @repo without calling git config" do
        # This must not raise, even though git config is stubbed to raise
        service = described_class.new(token: fake_token)
        # open_pr with no files returns nil without any Octokit calls; all this
        # example needs is that the service started up using the env var
        result = service.open_pr(branch: "b", title: "t", body: "b", files: {})
        expect(result).to be_nil
      end

      it "uses the GITHUB_REPO value for Octokit calls" do
        allow(octokit_client).to receive(:repo).with("owner/sway-repo").and_return(GHRepo.new("main"))
        allow(octokit_client).to receive(:ref).with("owner/sway-repo", anything).and_return(
          GHRef.new(GHObject.new("sha123"))
        )
        allow(octokit_client).to receive(:commit).with("owner/sway-repo", "sha123").and_return(
          GHCommit.new("sha123", GHCommitDetail.new(GHTree.new("tree123")))
        )
        allow(octokit_client).to receive(:create_ref).and_return(nil)
        allow(octokit_client).to receive(:create_blob).and_return("blob123")
        allow(octokit_client).to receive(:create_tree).and_return(GHTree.new("t2"))
        allow(octokit_client).to receive(:create_commit).and_return(
          GHGitCommit.new("c2", GHTree.new("t3"))
        )
        allow(octokit_client).to receive(:update_ref).and_return(nil)
        allow(octokit_client).to receive(:create_pull_request).and_return(GHPR.new(1, nil))

        service = described_class.new(token: fake_token)
        service.open_pr(branch: "seeds/test", title: "T", body: "B", files: {"f.json" => "{}"})

        expect(octokit_client).to have_received(:create_pull_request)
          .with("owner/sway-repo", anything, anything, anything, anything)
      end
    end

    context "when GITHUB_REPO env var is absent and git remote is available" do
      before do
        # GITHUB_REPO is not set, so the code falls through to git config
        allow(EnvSecret).to receive(:read).with("GITHUB_REPO").and_return(nil)
        allow(EnvSecret).to receive(:fetch!).with("GITHUB_TOKEN").and_return(fake_token)
        stub_git_remote { ["git@github.com:Plebeian-Technology/sway.git\n", "", instance_double(Process::Status, success?: true)] }
      end

      it "resolves @repo to Plebeian-Technology/sway from the SSH remote and uses it for Octokit calls" do
        # An earlier version called open_pr(files: {}), returning nil before
        # @repo is used — so SSH-URL parsing was never checked. This opens a
        # real PR so the parsed name reaches Octokit.
        allow(octokit_client).to receive(:repo).with("Plebeian-Technology/sway").and_return(GHRepo.new("main"))
        allow(octokit_client).to receive(:ref).with("Plebeian-Technology/sway", anything).and_return(
          GHRef.new(GHObject.new("sha123"))
        )
        allow(octokit_client).to receive(:commit).with("Plebeian-Technology/sway", "sha123").and_return(
          GHCommit.new("sha123", GHCommitDetail.new(GHTree.new("tree123")))
        )
        allow(octokit_client).to receive(:create_ref).and_return(nil)
        allow(octokit_client).to receive(:create_blob).and_return("blob123")
        allow(octokit_client).to receive(:create_tree).and_return(GHTree.new("t2"))
        allow(octokit_client).to receive(:create_commit).and_return(
          GHGitCommit.new("c2", GHTree.new("t3"))
        )
        allow(octokit_client).to receive(:update_ref).and_return(nil)
        allow(octokit_client).to receive(:create_pull_request).and_return(GHPR.new(1, nil))

        service = described_class.new(token: fake_token)
        service.open_pr(branch: "seeds/test", title: "T", body: "B", files: {"f.json" => "{}"})

        expect(octokit_client).to have_received(:create_pull_request)
          .with("Plebeian-Technology/sway", anything, anything, anything, anything)
      end
    end

    context "when GITHUB_REPO env var is absent and git remote returns empty string" do
      before do
        allow(EnvSecret).to receive(:read).with("GITHUB_REPO").and_return(nil)
        allow(EnvSecret).to receive(:fetch!).with("GITHUB_TOKEN").and_return(fake_token)
        stub_git_remote { ["\n", "", instance_double(Process::Status, success?: false)] }
      end

      it "raises an ArgumentError when both ENV and git remote are unavailable" do
        expect { described_class.new(token: fake_token) }.to raise_error(ArgumentError, /GITHUB_REPO/)
      end
    end
  end

  # -------------------------------------------------------------------
  # Rate limit rescue
  # -------------------------------------------------------------------
  describe "#open_pr with GitHub rate limit" do
    # Build a TooManyRequests error using allocate to bypass the constructor
    let(:rate_limit_error) { Octokit::TooManyRequests.allocate }

    before do
      # @lat: [[error-reporting-in-tests#Why Sentry's methods are watched rather than the constant replaced]]
      allow(Sentry).to receive(:capture_exception)
      allow(octokit_client).to receive(:repo).with(repo_name).and_return(repo_double)
      allow(octokit_client).to receive(:ref).with(repo_name, "heads/#{default_branch_name}")
        .and_return(base_ref_double)
      allow(octokit_client).to receive(:commit).with(repo_name, base_commit_sha)
        .and_return(make_commit(base_commit_sha, base_tree_sha))
      allow(octokit_client).to receive(:create_ref).and_raise(rate_limit_error)
    end

    it "logs an error, calls Sentry, and re-raises" do
      service = described_class.new(token: fake_token)

      expect(SwayLogging).to receive(:log_exception).with("github_pr.rate_limited", exception: anything)

      expect do
        service.open_pr(
          branch: "seeds/test",
          title: "T", body: "B",
          files: {"path/file.json" => "{}"}
        )
      end.to raise_error(Octokit::TooManyRequests)

      expect(Sentry).to have_received(:capture_exception).once
    end
  end
end
