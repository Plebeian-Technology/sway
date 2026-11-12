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
        items = feed_query.items
        FeedItemResource.new(items, params: bill_count_params(items)).serializable_hash
      },
      feed_search: query,
      newest_keys: InertiaRails.optional { # steep:ignore
        FeedQuery.new(user:, query:).items.map(&:key)
      }
    }
  end

  private

  def bill_count_params(items)
    bill_ids = items.filter_map { |item| item.bill&.id }.uniq
    return {vote_counts_by_bill_id: {}, view_counts_by_bill_id: {}, share_counts_by_bill_id: {}} if bill_ids.empty?

    vote_counts_by_bill_id = BillScore.where(bill_id: bill_ids)
      .pluck(:bill_id, :for, :against)
      .to_h { |bill_id, for_count, against_count| [bill_id, for_count + against_count] }
    view_counts_by_bill_id = BillView.where(bill_id: bill_ids).group(:bill_id).count
    share_counts_by_bill_id = UserBillShare.where(bill_id: bill_ids).group(:bill_id).distinct.count(:user_id)

    {
      vote_counts_by_bill_id:,
      view_counts_by_bill_id:,
      share_counts_by_bill_id:
    }
  end
end
