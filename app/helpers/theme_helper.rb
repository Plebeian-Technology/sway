# frozen_string_literal: true

# @lat: [[theme-mode-and-theme-id-resolution#Theme id: sway, classic, chamber, and so on]]
module ThemeHelper
  COOKIE_NAME = :sway_theme
  VALID_PREFERENCES = %w[auto light dark].freeze
  DEFAULT_PREFERENCE = "light"

  # @lat: [[theme-test-suite-silent-failure-guards#Theme-id allowlist: two hand-maintained lists with nothing generating one from the other]]
  THEME_ID_COOKIE_NAME = :sway_theme_id
  VALID_THEME_IDS = %w[sway banner ballot cornerstore monochrome service-manual swiss-grid].freeze
  DEFAULT_THEME_ID = "sway"

  # @lat: [[theme-font-hrefs#Why the layout requests only the active theme's fonts]]
  THEME_FONT_HREFS = {
    "banner" => "https://fonts.googleapis.com/css2?family=Mona+Sans:wght@400;500;600;700;800&family=DM+Serif+Display:ital@0;1&display=swap",
    "ballot" => "https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@400;500;600;700;800&family=Barlow:wght@400;500;600;700&display=swap",
    "cornerstore" => "https://fonts.googleapis.com/css2?family=Alfa+Slab+One&family=Libre+Franklin:wght@400;700;800;900&display=swap",
    "monochrome" => "https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600;700&family=Inter:wght@400;500;600;700;800&display=swap",
    "service-manual" => "https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600;700&family=Inter:wght@400;500;600;700;800&display=swap",
    "swiss-grid" => "https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600;700&family=Inter:wght@400;500;600;700;800&display=swap"
  }.freeze

  def theme_font_stylesheet_href
    THEME_FONT_HREFS[theme_id]
  end

  def theme_preference
    db = current_user&.theme_mode
    return db if db && VALID_PREFERENCES.include?(db)

    cookie = cookies.signed[COOKIE_NAME]
    return cookie if VALID_PREFERENCES.include?(cookie)

    DEFAULT_PREFERENCE
  end

  def theme_html_class
    (theme_preference == "dark") ? "dark" : nil
  end

  def theme_id
    cookie = cookies.signed[THEME_ID_COOKIE_NAME]
    return cookie if VALID_THEME_IDS.include?(cookie)

    DEFAULT_THEME_ID
  end
end
