# frozen_string_literal: true

# @lat: [[github-pr-service-design#Why GITHUB_REPO is read with EnvSecret.read, not ENV.fetch with a block]]
class GitHubPrService
  # @lat: [[github-pr-service-design#Why GITHUB_REPO is read with EnvSecret.read, not ENV.fetch with a block]]
  GIT_TIMEOUT_SECONDS = 10

  def initialize(token: EnvSecret.fetch!("GITHUB_TOKEN"))
    @client = Octokit::Client.new(access_token: token)
    # @lat: [[github-pr-service-design#Why GITHUB_REPO is read with EnvSecret.read, not ENV.fetch with a block]]
    @repo = EnvSecret.read("GITHUB_REPO") || repo_from_git_remote
  end

  def open_pr(branch:, title:, body:, files:)
    return nil if files.empty?

    base_ref = @client.ref(@repo, "heads/#{default_branch}")
    base_sha = base_ref.object.sha

    # @lat: [[github-pr-service-design#Why base_tree must be a tree id, not a commit id]]
    base_tree_sha = @client.commit(@repo, base_sha).commit.tree.sha

    @client.create_ref(@repo, "refs/heads/#{branch}", base_sha)

    current_commit_sha = base_sha

    files.each do |path, content|
      # @lat: [[github-pr-service-design#Why create_blob's return value is read as blob.sha, not .sha directly]]
      blob_sha = @client.create_blob(@repo, Base64.strict_encode64(content), "base64")

      tree = @client.create_tree(
        @repo,
        [{path: path, mode: "100644", type: "blob", sha: blob_sha}],
        base_tree: base_tree_sha
      )

      commit = @client.create_commit(
        @repo,
        "chore(seeds): refresh legislators #{Date.current}",
        tree.sha,
        current_commit_sha
      )

      @client.update_ref(@repo, "heads/#{branch}", commit.sha)

      # @lat: [[github-pr-service-design#What open_pr(branch:, title:, body:, files:) promises]]
      current_commit_sha = commit.sha
      # @lat: [[github-pr-service-design#Why current_commit_sha and base_tree_sha are reassigned after every file]]
      base_tree_sha = commit.tree.sha
    end

    @client.create_pull_request(@repo, default_branch, branch, title, body)
  rescue Octokit::UnprocessableEntity => e
    # @lat: [[github-pr-service-design#What open_pr(branch:, title:, body:, files:) promises]]
    SwayLogging.log_exception("github_pr.branch_conflict", exception: e, branch: branch, level: :warn)
    raise
  rescue Octokit::TooManyRequests => e
    # @lat: [[github-pr-service-design#Why the rate-limit rescue is safe to log in full]]
    SwayLogging.log_exception("github_pr.rate_limited", exception: e)
    Sentry.capture_exception(e)
    raise
  end

  private

  def default_branch
    @default_branch ||= @client.repo(@repo).default_branch
  end

  # @lat: [[github-pr-service-design#Why repo_from_git_remote is production's fallback, never its primary path]]
  def repo_from_git_remote
    out, _err, _status = Sway::Subprocess.capture3(
      "git", "config", "--get", "remote.origin.url", timeout_seconds: GIT_TIMEOUT_SECONDS
    )
    slug = out.strip
      .delete_prefix("https://github.com/")
      .delete_prefix("git@github.com:")
      .delete_suffix(".git")

    if slug.empty?
      raise ArgumentError,
        "GITHUB_REPO env var is not set and git config returned an empty remote URL. " \
        "Set GITHUB_REPO=owner/repo in production."
    end

    slug
  end
end
