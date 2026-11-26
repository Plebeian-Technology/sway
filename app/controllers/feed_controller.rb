# frozen_string_literal: true

# @lat: [[home-feed#Serving the feed]]
class FeedController < ApplicationController
  def index
    user = current_user
    return redirect_or_json(root_path) if user.nil?

    cursor = params[:feed_cursor].presence&.to_s
    query = params[:feed_search].presence&.to_s

    if mobile_api_request?
      feed_query = page_feed_query(user:, query:, cursor:)
      items = feed_query.items
      render_inertia_or_json(
        page: Pages::FEED,
        props: {
          items: serialized_items(items),
          feed_cursor: feed_query.next_cursor,
          feed_search: query,
          feed_match_count: feed_query.match_count
        }
      )
    else
      render inertia: Pages::FEED, props: {
        items: -> {
          feed_query = page_feed_query(user:, query:, cursor:)
          InertiaRails.scroll( # steep:ignore
            page_name: "feed_cursor",
            current_page: cursor,
            next_page: feed_query.next_cursor,
            previous_page: nil
          ) {
            items = feed_query.items
            serialized_items(items)
          }
        },
        feed_search: query,
        feed_match_count: -> { page_feed_query(user:, query:, cursor:).match_count },
        newest_keys: InertiaRails.optional { # steep:ignore
          first_page_query(user:, query:).items.map(&:key)
        }
      }
    end
  end

  private

  def first_page_query(user:, query:)
    @first_page_query ||= FeedQuery.new(user:, query:)
  end

  def page_feed_query(user:, query:, cursor:)
    return first_page_query(user:, query:) if cursor.nil?

    @page_feed_query ||= FeedQuery.new(user:, query:, cursor:)
  end

  def serialized_items(items)
    summary_bills = items.filter_map { |item| item.bill if item.kind == "bill_of_the_month_released" }
    ActiveRecord::Associations::Preloader.new(
      records: summary_bills,
      associations: %i[bill_summary_revisions bill_llm_provisioning]
    ).call
    FeedItemResource.new(items, params: bill_count_params(items)).serializable_hash
  end

  def bill_count_params(items)
    bill_ids = items.filter_map { |item| item.bill&.id }.uniq
    return {view_counts_by_bill_id: {}, share_counts_by_bill_id: {}} if bill_ids.empty?

    view_counts_by_bill_id = BillView.where(bill_id: bill_ids).group(:bill_id).count
    share_counts_by_bill_id = UserBillShare.where(bill_id: bill_ids).group(:bill_id).distinct.count(:user_id)

    {
      view_counts_by_bill_id:,
      share_counts_by_bill_id:
    }
  end
end
