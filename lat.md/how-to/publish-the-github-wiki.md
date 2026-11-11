---
lat:
  mode: how-to
---

# Publish the GitHub Wiki from lat.md

The Diátaxis documentation in `lat.md/` compiles into GitHub's `<repo>.wiki.git` repository through [[scripts/github_wiki_builder.rb#GitHubWikiBuilder]] and `scripts/build-github-wiki.rb`. Why the builder rewrites links and flattens filenames is explained in [[github-wiki-sync]].

1. Enable **Wikis** in the GitHub repository's **Settings → General → Features** section, then open the **Wiki** tab on GitHub and click **Create the first page** → **Save Page** once so GitHub provisions `<repo>.wiki.git`.
2. Push changes under `lat.md/` to `main` (or trigger the **Sync GitHub Wiki** workflow manually in **Actions → Sync GitHub Wiki → Run workflow**). `.github/workflows/wiki-sync.yml` clones `<repo>.wiki.git`, runs `ruby scripts/build-github-wiki.rb`, commits the compiled pages and `_Sidebar.md`, and pushes them to the Wiki tab.
3. To preview or push the compiled wiki locally (for example, when publishing to the public repository), run `ruby scripts/build-github-wiki.rb <wiki-checkout-dir> Plebeian-Technology/sway main`, inspect `git -C <wiki-checkout-dir> status`, and push `origin HEAD`.
