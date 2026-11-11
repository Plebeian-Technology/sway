# frozen_string_literal: true

# @lat: [[news-article-evidence#Changes after publication]]
class NewsArticleTestimonyResource < ApplicationResource
  attributes :id, :author_name, :outlet_name, :stance

  attribute :url do |record|
    record.citation_url
  end

  attribute :argument do |record|
    record.argument_markdown
  end
end
