# frozen_string_literal: true

# @lat: [[home-feed#Serving the feed]]
class FeedController < ApplicationController
  def index
    user = current_user
    return redirect_to(root_path) if user.nil?

    cursor = params[:feed_cursor].presence&.to_s
    query = params[:feed_search].presence&.to_s
    feed_query = FeedQuery.new(user:, query:, cursor:)

    render inertia: Pages::FEED, props: {
      items: InertiaRails.scroll( # steep:ignore
        page_name: "feed_cursor",
        current_page: cursor,
        next_page: feed_query.next_cursor,
        previous_page: nil
      ) {
        FeedItemResource.new(feed_query.items).serializable_hash
      },
      feed_search: query
    }
  end
end
