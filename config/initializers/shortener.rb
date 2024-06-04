# https://github.com/jpmcgrath/shortener?tab=readme-ov-file#configuration-

Shortener.unique_key_length = 8

Shortener.default_redirect = "/"

Shortener.charset = ("a".."z").to_a + (0..9).to_a + ["-", "_"]

Shortener.auto_clean_url = true
