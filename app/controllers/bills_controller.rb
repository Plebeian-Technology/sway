# frozen_string_literal: true
# typed: true

class BillsController < ApplicationController
  include SwayGoogleCloudStorage

  before_action :verify_is_admin, only: %i[new edit create update destroy]
  before_action :set_bill, only: %i[show edit update destroy]

  # GET /bills or /bills.json
  def index
    T.unsafe(self).render_bills(lambda do
      {
        bills: current_sway_locale&.bills&.map { |b| b.to_builder.attributes! } || []
      }
    end)
  end

  # GET /bills/1 or /bills/1.json
  def show
    if @bill.present?
      T.unsafe(self).render_bill(-> { @bill.render(current_user) })
    else
      redirect_to bills_path
    end
  end

  # ADMIN ONLY ROUTES

  # GET /bills/new
  def new
    T.unsafe(self).render_bill_creator({
      bills: (current_sway_locale&.bills || []).map { |b| b.to_builder.attributes! },
      bill: Bill.new.attributes,
      legislators: (current_sway_locale&.legislators || []).map do |l|
                     l.to_builder.attributes!
                   end,
      legislatorVotes: [],
      organizations: Organization.where(sway_locale: current_sway_locale).map { |o| o.to_builder(with_positions: false).attributes! },
      tabKey: params[:tab_key]
    })
  end

  # GET /bills/1/edit
  def edit
    redirect_to new_bill_path if @bill.blank?

    T.unsafe(self).render_bill_creator({
      bills: (current_sway_locale&.bills || []).map { |b| b.to_builder.attributes! },
      bill: @bill.to_builder.attributes!.tap do |b|
        b[:organizations] = @bill.organizations.map do |organization|
          organization.to_builder(with_positions: true).attributes!
        end
      end,
      legislators: (current_sway_locale&.legislators || []).map do |l|
                     l.to_builder.attributes!
                   end,
      legislatorVotes: @bill.legislator_votes.map { |lv| lv.to_builder.attributes! },
      organizations: Organization.where(sway_locale: current_sway_locale).map { |o| o.to_builder(with_positions: false).attributes! },
      tabKey: params[:tab_key]
    })
  end

  # POST /bills or /bills.json
  def create
    b = Bill.find_or_initialize_by(
      external_id: bill_params[:external_id],
      sway_locale_id: bill_params[:sway_locale_id] || current_sway_locale.presence&.id
    )

    b.assign_attributes(**bill_params.except(*vote_params))

    b.legislator = Legislator.find(bill_params[:legislator_id])

    if b.save
      create_vote(b)

      redirect_to edit_bill_path(b.id, {saved: "Bill Created", event_key: "legislator_votes"}), inertia: {errors: {}}
    else
      redirect_to new_bill_path({event_key: "bill"}), inertia: {
        errors: b.errors
      }
    end
  rescue Exception => e # rubocop:disable Lint/RescueException
    Rails.logger.error(e)
    redirect_to new_bill_path({event_key: "bill"}), inertia: {errors: {external_id: e}}
  end

  # PATCH/PUT /bills/1 or /bills/1.json
  def update
    if @bill.blank?
      return redirect_to new_bill_path({event_key: "bill"})
    end

    current_audio_path = @bill.audio_bucket_path.freeze
    if @bill.update(bill_params.except(*vote_params))
      remove_audio(current_audio_path)

      create_vote(@bill)

      redirect_to edit_bill_path(@bill.id, {saved: "Bill Updated", event_key: "legislator_votes"})
    else
      redirect_to edit_bill_path(@bill.id, {event_key: "bill"}), inertia: {
        errors: b.errors
      }
    end
  end

  # DELETE /bills/1 or /bills/1.json
  def destroy
    @bill.destroy!

    new
  end

  private

  def set_bill
    @bill = Bill.includes(:legislator_votes, :organization_bill_positions, :legislator, :sway_locale).find(params[:id])
  end

  def remove_audio(audio_path)
    return unless @bill.audio_bucket_path != audio_path

    delete_file(
      bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS],
      file_name: audio_path
    )
  end

  def create_vote(b)
    return unless bill_params[:house_roll_call_vote_number] || bill_params[:senate_roll_call_vote_number]

    Vote.find_or_create_by!(bill_id: b.id,
      house_roll_call_vote_number: bill_params[:house_roll_call_vote_number],
      senate_roll_call_vote_number: bill_params[:senate_roll_call_vote_number])
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
      :level,
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
      :audio_by_line
    )
  end

  def vote_params
    [
      :house_roll_call_vote_number,
      :senate_roll_call_vote_number
    ]
  end

  def legislator_vote_params
    params.require(:legislator_votes).map do |p|
      p.transform_keys(&:underscore).permit(:legislator_id, :bill_id, :support)
    end
  end

  def organizations_params
    params.require(:organizations).map do |p|
      p.transform_keys(&:underscore).permit(
        :id, :sway_locale_id, :name, :icon_path, positions: [:id, :bill_id, :summary, :support]
      )
    end
  end

  def params
    super.transform_keys(&:underscore)
  end

  def remove_icon(organization, current_icon_path)
    return unless organization.icon_path != current_icon_path

    delete_file(bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS], file_name: current_icon_path)
  end
end
