# Testimony fixtures

The two testimony bundles under `spec/fixtures/testimony/` are real letters to Baltimore City Council, so they stay on the maintainer's machine and out of the repository.

## Why the testimony fixtures are local-only

`campaign_bundle.txt` and `no_campaign_bundle.txt` hold public testimony that carries private residents' names, email addresses and home addresses. The repository is published, so `.gitignore` keeps both files untracked.

The specs that read them go through [[spec/support/testimony_fixtures.rb#TestimonyFixtures]]. When a file is missing, the loader skips the running example with a message naming the file, the same way browser specs skip when no Chrome binary is present. A fresh clone and CI therefore pass, and a maintainer with the files on disk still runs every example.

A skip shows as pending, not as a failure, so a missing file on the maintainer's own machine is easy to overlook. The skip message names the file for that reason.

Inline test strings that once copied senders from these letters now use synthetic names, `example.*` mailboxes and `Example Street` addresses. Where a test depends on the class of a sender's domain, the domain stays and only the mailbox name is synthetic.
