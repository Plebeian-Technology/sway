# frozen_string_literal: true
# typed: true

class BillsController < ApplicationController
  include SwayGoogleCloudStorage

  skip_before_action :authenticate_sway_user!, only: %i[index show]

  before_action :verify_is_sway_admin, only: %i[new edit create update destroy]
  before_action :set_bill, only: %i[show edit update destroy]
  before_action :meta_title

  # GET /bills or /bills.json
  def index
    user_votes_by_bill_id = current_user&.user_votes&.index_by(&:bill_id)

    render_component(
      Pages::BILLS,
      lambda do
        {
          bills:
            Bill
              .previous(current_sway_locale)
              .map do |bill|
                bill.to_sway_json.merge(
                  {
                    user_vote: user_votes_by_bill_id&.dig(bill.id),
                    bill_score:
                      bill
                        .bill_score
                        &.to_builder_with_user(current_user)
                        &.attributes!
                        &.except("is_a?"),
                  },
                )
              end,
          districts:
            current_user&.districts(current_sway_locale)&.map(&:to_sway_json) ||
              [],
        }
      end,
    )
  end

  # GET /bills/1 or /bills/1.json
  def show
    if @bill.present?
      render_component(
        Pages::BILL,
        -> do
          to_render = @bill.render(current_user, current_sway_locale)
          if params[:with]&.include?("legislator")
            to_render[:legislator] = current_user&.legislators(
              current_sway_locale,
            )&.first
          end
          to_render
        end,
      )
    else
      redirect_to bills_path
    end
  end

  # ADMIN ONLY ROUTES

  # GET /bills/new
  def new
    render_component(
      Pages::BILL_CREATOR,
      {
        bills: Bill.current_session(current_sway_locale)&.map(&:to_sway_json),
        bill: Bill.new.attributes,
        legislators: current_sway_locale&.legislators&.map(&:to_sway_json),
        legislator_votes: [],
        organizations:
          Organization.where(sway_locale: current_sway_locale).map(
            &:to_sway_json
          ),
        tab_key: params[:tab_key],
      },
    )
  end

  # GET /bills/1/edit
  def edit
    return redirect_to new_bill_path if @bill.blank? || @bill.id.blank?

    render_component(
      Pages::BILL_CREATOR,
      {
        bills: Bill.current_session(current_sway_locale)&.map(&:to_sway_json),
        bill:
          @bill.to_sway_json.tap do |b|
            b[:organizations] = @bill.organizations.map(&:to_sway_json)
          end,
        legislators:
          current_sway_locale
            &.legislators
            &.filter do |l|
              if current_sway_locale&.congress? &&
                   @bill.external_id.starts_with?("PN")
                l.active && !l.title.starts_with?("Rep")
              else
                l.active
              end
            end
            &.map(&:to_sway_json),
        legislator_votes: @bill.legislator_votes.map(&:to_sway_json),
        organizations:
          Organization.where(sway_locale: current_sway_locale).map(
            &:to_sway_json
          ),
        tab_key: params[:tab_key],
      },
    )
  end

  # POST /bills or /bills.json
  def create
    b =
      Bill.find_by(
        external_id: bill_params[:external_id],
        sway_locale_id: bill_params[:sway_locale_id] || current_sway_locale&.id,
      )
    b = Bill.new(**bill_params.except(*vote_params)) if b.nil?

    b.legislator = Legislator.find(bill_params[:legislator_id])

    if b.save
      create_vote(b)
      route_component(
        edit_bill_path(
          b.id,
          { saved: "Bill Created", event_key: "legislator_votes" },
        ),
      )
    else
      Rails.logger.error(
        "Error saving bill - #{b.errors.flat_map(&:message).join(" | ")}",
      )
      redirect_to new_bill_path({ event_key: "bill" }),
                  inertia: {
                    errors: b.errors,
                  }
    end
  rescue Exception => e # rubocop:disable Lint/RescueException
    Rails.logger.error(e)
    redirect_to new_bill_path({ event_key: "bill" }),
                inertia: {
                  errors: {
                    external_id: e,
                  },
                }
  end

  # PATCH/PUT /bills/1 or /bills/1.json
  def update
    return redirect_to new_bill_path({ event_key: "bill" }) if @bill.blank?

    current_audio_path = @bill.audio_bucket_path.freeze
    if @bill.update(bill_params.except(*vote_params))
      remove_audio(current_audio_path)

      create_vote(@bill)

      route_component(
        edit_bill_path(
          @bill.id,
          { saved: "Bill Updated", event_key: "legislator_votes" },
        ),
      )
    else
      redirect_to edit_bill_path(@bill.id, { event_key: "bill" }),
                  inertia: {
                    errors: @bill.errors,
                  }
    end
  end

  # DELETE /bills/1 or /bills/1.json
  def destroy
    @bill&.destroy!

    new
  end

  def meta_title
    @meta_title =
      case action_name
      when "index"
        if current_sway_locale.present?
          "#{current_sway_locale&.human_name} Legislation"
        else
          "Sway Legislation"
        end
      when "show"
        if @bill.present? && current_sway_locale.present?
          "#{@bill.external_id} - #{current_sway_locale&.human_name}"
        else
          "Sway Legislation"
        end
      else
        "Sway"
      end
  end

  private

  def set_bill
    @bill =
      T.let(
        Bill.includes(
          :legislator_votes,
          :organization_bill_positions,
          :legislator,
          :sway_locale,
        ).find(params[:id]),
        T.nilable(Bill),
      )
  end

  def remove_audio(audio_path)
    return unless @bill.present? && @bill.audio_bucket_path != audio_path

    delete_file(
      bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS],
      file_name: audio_path,
    )
  end

  def create_vote(b)
    unless bill_params[:house_roll_call_vote_number] ||
             bill_params[:senate_roll_call_vote_number]
      return
    end

    Vote.find_or_create_by!(
      bill_id: b.id,
      house_roll_call_vote_number: bill_params[:house_roll_call_vote_number],
      senate_roll_call_vote_number: bill_params[:senate_roll_call_vote_number],
    )
  end

  # Only allow a list of trusted parameters through.
  def bill_params
    params.transform_keys(&:underscore).permit(
      :external_id,
      :external_version,
      :title,
      :link,
      :chamber,
      :introduced_date_time_utc,
      :house_vote_date_time_utc,
      :senate_vote_date_time_utc,
      :category,
      :summary,
      :status,
      :active,
      :audio_bucket_path,
      :audio_by_line,
      :sway_locale_id,
      :legislator_id,
      :house_roll_call_vote_number,
      :senate_roll_call_vote_number,
      :audio_bucket_path,
      :audio_by_line,
    )
  end

  def vote_params
    %i[house_roll_call_vote_number senate_roll_call_vote_number]
  end

  def legislator_vote_params
    params
      .require(:legislator_votes)
      .map do |p|
        p.transform_keys(&:underscore).permit(
          :legislator_id,
          :bill_id,
          :support,
        )
      end
  end

  def organizations_params
    params
      .require(:organizations)
      .map do |p|
        p.transform_keys(&:underscore).permit(
          :id,
          :sway_locale_id,
          :name,
          :icon_path,
          positions: %i[id bill_id summary support],
        )
      end
  end

  def params
    super.transform_keys(&:underscore)
  end

  sig do
    params(
      organization: Organization,
      current_icon_path: T.nilable(String),
    ).void
  end
  def remove_icon(organization, current_icon_path)
    return unless organization.icon_path != current_icon_path

    delete_file(
      bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS],
      file_name: current_icon_path,
    )
  end
end
