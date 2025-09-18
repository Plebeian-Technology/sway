module DefaultMetaTaggable
  extend ActiveSupport::Concern

  included { inertia_share { meta_inertia_data } }

  def meta_title
    @meta_title || "Sway"
  end

  def meta_description
    @meta_title || "Remember in November"
  end

  def meta_tags
    @meta_tags || default_meta_tags
  end

  def set_meta_tag(tag_name, value)
    @meta_tags ||= default_meta_tags
    @meta_tags[tag_name.to_s] = value
  end

  def default_meta_tags
    {
      "description" => meta_description,
      "author" => "Plebeian Technologies, Inc.",
      "title" => meta_title,
      "og:description" => meta_description,
      "og:type" => "website",
      "og:title" => meta_title,
      "og:image" => "https://sway.vote/images/sway-us-light.png",
      "og:image:secure_url" => "https://sway.vote/images/sway-us-light.png",
      "og:url" => request.original_url,
      "twitter:title" => meta_title,
      "twitter:description" => meta_description,
      "twitter:image" => "https://sway.vote/images/sway-us-light.png",
      "twitter:card" => "summary_large_image",
    }
  end

  def meta_inertia_data
    {
      title: -> { meta_title },
      meta:
        lambda do
          meta_tags.map do |tag_name, value|
            id_key = tag_name.start_with?("og") ? :property : :name
            {}.tap do |h|
              h[id_key] = tag_name.to_s
              h[:content] = value
            end
          end
        end,
    }
  end
end
