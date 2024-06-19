# https://github.com/paper-trail-gem/paper_trail?tab=readme-ov-file#1e-configuration

PaperTrail.config.enabled = true # default
PaperTrail.config.has_paper_trail_defaults = {
  on: %i[create update destroy] # default
}
PaperTrail.config.version_limit = 3 # default
