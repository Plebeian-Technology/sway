# frozen_string_literal: true

class BillsController < ApplicationController
  include SwayGoogleCloudStorage
  include LegislationPipelineRunSourcing
  include RecordsBillViews

  skip_before_action :authenticate_sway_user!, only: %i[index show past_of_the_month]

  before_action :verify_is_sway_admin,
    only: %i[
      new
      edit
      create
      update
      destroy
      generate_summary
      regenerate_summary
      supplemental_testimony
      testimony_letter_stance
      approve_org_position
      run_pipeline
      cancel_pipeline_run_bill
      sweep_stale_pipeline_runs
      resume_pipeline_run
      restart_pipeline_run
      paste_summary
      restore_summary_revision
    ]

  before_action :set_bill_for_show, only: %i[show]
  before_action :set_bill,
    only: %i[
      edit
      update
      destroy
      generate_summary
      regenerate_summary
      supplemental_testimony
      testimony_letter_stance
      approve_org_position
      paste_summary
      restore_summary_revision
    ]
  before_action :meta_title

  # @lat: [[bills-controller-design#BillsController design#The web bills index grows a stable page window]]
  BILLS_INDEX_PAGE_SIZE = 24

  # @lat: [[mobile-bill-creator#Each tab gets only its own props]]
  BILL_CREATOR_TAB_PROPS = {
    "creator" => %i[
      bill bill_id tab_key legislators legislator_votes legislator_votes_refreshed_at legislator_votes_source
      organizations news_articles
    ],
    "schedule" => %i[bill bill_id bills],
    "pipeline" => %i[
      bill bill_id bills pipeline_preview selected_stages download_missing_assets testimony_coverage
      testimony_campaign_drafts sending_service_domains sending_service_domains_total bill_artifact_mirrors
      fetched_bills activity_log_entries activity_log_next_cursor activity_log_has_more legislation_pipeline_run
      recent_pipeline_runs stale_pipeline_run_count orphan_pipeline_run_count
    ],
    "summary" => %i[
      bill bill_id summary_model_options current_summarization_model current_summarization_reasoning_effort
      summary_sources active_categories max_active_categories_per_bill news_articles receipt_status
      review_draft_revision active_legislation_pipeline_run summary_prompt summary_revisions summary_source_documents
    ],
    "positions" => %i[
      bill bill_id tab_key organizations testimony_coverage testimony_campaign_drafts
      testimony_claimed_affiliations campaigns campaign_organization_candidates public_testimony_counts
    ]
  }.freeze

  # @lat: [[mobile-bill-creator#Each tab gets only its own props]]
  BILL_PICKER_PROPS = %i[bills].freeze

  STALE_SUMMARY_RESTORE_ALERT = "The bill summary was modified by another operator. Please review before restoring."

  def index
    # @lat: [[bills-controller-design#BillsController design#Why the search and sort labels in parityCopy.ts note the underlying split]]
    allowed_sort_columns = %w[
      title
      introduced_date_time_utc
      house_vote_date_time_utc
    ]
    raw_sort = bills_sort_param
    sort_column =
      if allowed_sort_columns.include?(raw_sort)
        raw_sort
      else
        "introduced_date_time_utc"
      end
    sort_direction = (bills_direction_param == "asc") ? "asc" : "desc"
    index_scope = bills_index_scope

    render_inertia_or_json(
      page: Pages::BILLS,
      props: {
        # @lat: [[lazy-inertia-props#Lazy Inertia props#Current optional and deferred JSON props]]
        all_categories: Category.where(active: true).order(:name).pluck(:name),
        bills_total: index_scope.count,
        list_mode: bills_list_mode,
        legislative_sessions: legislative_sessions_prop,
        selected_legislative_session_id: selected_legislative_session_id_prop,
        bills:
          InertiaRails.defer do
            # @lat: [[lazy-inertia-props#Lazy Inertia props#Current optional and deferred JSON props]]
            user = current_user
            user_votes_by_bill_id = user&.user_votes&.index_by(&:bill_id)

            bills_query =
              index_scope.includes(
                :roll_calls,
                # @lat: [[scores-and-agreement#Scores and agreement#Bill score builders receive one district snapshot]]
                {bill_score: {bill_score_districts: :district}},
                :categories,
                :legislative_session,
                :bill_llm_provisioning,
                :bill_summary_revisions
              )

            # @lat: [[scores-and-agreement#Scores and agreement#Bill score builders receive one district snapshot]]
            user_districts =
              if current_sway_locale
                user&.districts(current_sway_locale) ||
                  [current_sway_locale.at_large_district].compact
              end

            # @lat: [[bills-controller-design#BillsController design#The web bills index grows a stable page window]]
            page_param = bills_page_param
            window =
              if !mobile_api_request? || page_param.present?
                [page_param.to_i, 1].max * BILLS_INDEX_PAGE_SIZE
              end #: Integer?

            ordered =
              bills_query.reorder(
                # @lat: [[bills-controller-design#BillsController design#The web bills index grows a stable page window]]
                sort_column => sort_direction.to_sym, :id => :desc
              )
            ordered = ordered.limit(window) if window

            ordered
              .map do |bill|
                bill.to_sway_json.merge(
                  {
                    # @lat: [[bills-controller-design#BillsController design#The index embeds user votes through a whitelist resource]]
                    user_vote: user_votes_by_bill_id&.dig(bill.id)&.then { |uv|
                      UserVoteResource.new(uv).serializable_hash
                    },
                    bill_score:
                      bill
                        .bill_score
                        &.to_builder_with_user(user, user_districts: user_districts)
                        &.attributes!
                        &.except("is_a?")
                  }
                )
              end
          end,

        filters: {
          search: bills_search_param,
          sort: bills_sort_param,
          direction: bills_direction_param
        }
      }
    )
  end

  # @lat: [[bills-controller-design#The web bills index grows a stable page window#Past Bills of the Month vs All Bills and historical sessions]]
  def past_of_the_month
    index
  end

  def show
    record_bill_view(@bill)
    to_render = @bill.render(current_user, current_sway_locale, district_legislator_names: mobile_api_request?)
    enrich_with_first_legislator!(to_render)

    # @lat: [[outbound-email#Outbound email#The preview is built from the object the mailer renders]]
    user_legislators =
      current_user&.user_legislators_by_locale(@bill.sway_locale) || []
    if user_legislators.any? && @bill.active
      to_render[:email_preview] =
        LegislatorEmailText.new(
          UserLegislatorEmail.new(user_legislator: user_legislators.first, bill: @bill)
        ).as_props
      to_render[:user_legislator_emails] =
        UserLegislatorEmailResource.new(
          UserLegislatorEmail
            .where(bill: @bill, user_legislator: user_legislators)
            .includes(user_legislator: :legislator)
        ).serializable_hash
    end

    render_inertia_or_json(page: Pages::BILL, props: to_render)
  end

  # @lat: [[lazy-inertia-props#Lazy Inertia props]]
  def new
    render_inertia_or_json(page: Pages::BILL_CREATOR,
      props: mobile_bill_creator_tab_props({
        bills: -> {
          picker_bills(Bill.where(sway_locale: current_sway_locale).order(introduced_date_time_utc: :desc, external_id: :desc))
        },
        activity_log_entries: -> { activity_log_entries_prop[:entries] },
        activity_log_next_cursor: -> { activity_log_entries_prop[:next_cursor] },
        activity_log_has_more: -> { activity_log_entries_prop[:has_more] },
        bill: -> { Bill.new.attributes },
        # @lat: [[legislator-photo-prefetch#Prefetching a reader's own legislator photos#Why the photo attachment and blob are preloaded]]
        legislators: -> {
          current_sway_locale&.legislators&.with_active_term&.preload(photo_attachment: :blob)&.map(&:to_sway_json)
        },
        legislator_votes: -> { [] },
        organizations: -> {
          Organization
            .with_attached_icon
            .includes(organization_bill_positions: :bill)
            .where(sway_locale: current_sway_locale)
            .map(&:to_sway_json)
        },
        tab_key: -> { bill_creator_tab_param },
        pipeline_preview: -> { pipeline_preview_for(@bill) },
        fetched_bills: -> { ::BillCreator::FetchedBillsPanelSerializer.call(current_sway_locale) },
        selected_stages: -> { pipeline_controls_state[:selected_stages] },
        bill_id: -> { pipeline_controls_state[:bill_id] },
        download_missing_assets: -> { pipeline_controls_state[:download_missing_assets] },
        news_articles: -> { [] },
        receipt_status: -> {}
      }))
  end

  # @lat: [[lazy-inertia-props#Lazy Inertia props#Current optional and deferred JSON props]]
  def edit
    # @lat: [[legislation-pipeline#The legislation pipeline#Artifacts are files, not rows]]
    # @lat: [[fetched-bills-panel#What has actually been fetched to disk]]
    props = bill_creator_props.merge(
      activity_log_entries: -> { activity_log_entries_prop[:entries] },
      activity_log_next_cursor: -> { activity_log_entries_prop[:next_cursor] },
      activity_log_has_more: -> { activity_log_entries_prop[:has_more] },
      bill_artifact_mirrors: -> { ::BillCreator::ResourceCachePanelSerializer.call(@bill) },
      fetched_bills: -> { ::BillCreator::FetchedBillsPanelSerializer.call(@bill&.sway_locale || current_sway_locale) }
    )
    render_inertia_or_json(page: Pages::BILL_CREATOR, props: mobile_bill_creator_tab_props(props))
  end

  def create
    b =
      Bill.find_by(
        external_id: bill_params[:external_id],
        sway_locale_id: bill_params[:sway_locale_id] || current_sway_locale&.id
      )
    b = Bill.new(**bill_params.except(*vote_params)) if b.nil?

    b.legislator = Legislator.find(bill_params[:legislator_id])

    if b.save
      create_vote(b)
      # @lat: [[bootstrap-caching-and-rate-limiting#Why locale and featured bill are cached per locale]]
      Api::V1::BootstrapController.expire_botm_cache(b.sway_locale_id)
      # @lat: [[bill-creator-shell#The Bill Creator shell#Why the Bill Creator carries query parameters across navigation]]
      # @lat: [[mobile-bill-creator#Sections#The bill fields section]]
      respond_after_write(creator_bill_creator_path(b.id, {event_key: "legislator_votes"}),
        notice: "Bill Created",
        json: written_bill_json(b))
    else
      SwayLogging.error("bills.save_failed", errors: b.errors.full_messages)
      respond_after_write(new_bill_creator_path({event_key: "bill"}), errors: b.errors)
    end
  rescue => e
    # @lat: [[bills-controller-design#BillsController design#Bill creation rescues ordinary application failures]]
    SwayLogging.log_exception(
      "bills.create_failed",
      exception: e,
      external_id: bill_params[:external_id],
      sway_locale_id: bill_params[:sway_locale_id] || current_sway_locale&.id,
      legislator_id: bill_params[:legislator_id]
    )
    respond_after_write(new_bill_creator_path({event_key: "bill"}), errors: {external_id: e.message})
  end

  def update
    current_audio_path = @bill.audio_bucket_path.freeze
    previous_sway_locale_id = @bill.sway_locale_id
    success = false

    summary_param = bill_params[:summary]
    summary_changed = bill_params.key?(:summary) && summary_param != @bill.summary

    if summary_changed && summary_param.blank?
      @bill.errors.add(:summary, "can't be blank")
      return render_summary_publication_failure(
        ManualNewsSummaryPublicationService::Result.new(
          status: :missing_news_usage,
          errors: ["Summary can't be blank"]
        )
      )
    end

    if summary_changed && summary_param.present?
      pre_validation = ManualNewsSummaryPublicationService.publish!(
        bill: @bill,
        summary_markdown: summary_param,
        actor: current_user,
        origin: "operator_edit",
        news_usage: summary_publication_params[:news_usage],
        source_uses: summary_publication_params[:source_uses],
        snapshot_id: summary_publication_params[:news_source_snapshot_id],
        dry_run: true
      )

      unless pre_validation.published?
        snapshot = pre_validation.snapshot
        effective_snapshot = snapshot if snapshot && NewsArticleSourceSnapshot.exists?(snapshot.id)

        draft_rev = BillSummaryRevision.record_revision!(
          bill: @bill,
          summary_markdown: summary_param,
          actor: current_user,
          origin: "operator_edit",
          publication_role: "draft",
          review_state: "reviewed",
          news_source_snapshot: effective_snapshot
        )

        final_result = ManualNewsSummaryPublicationService::Result.new(
          status: pre_validation.status,
          errors: pre_validation.errors,
          reasons: pre_validation.reasons,
          revision: draft_rev,
          snapshot: effective_snapshot,
          grounding_result: pre_validation.grounding_result,
          eligibility_comparison: pre_validation.eligibility_comparison
        )

        return render_summary_publication_failure(final_result)
      end
    end

    publication_failed = false
    # @type var summary_pub_result: ManualNewsSummaryPublicationService::Result?
    summary_pub_result = nil

    ActiveRecord::Base.transaction do
      if summary_changed && summary_param.present?
        pub_result = ManualNewsSummaryPublicationService.publish!(
          bill: @bill,
          summary_markdown: summary_param,
          actor: current_user,
          origin: "operator_edit",
          news_usage: summary_publication_params[:news_usage],
          source_uses: summary_publication_params[:source_uses],
          snapshot_id: summary_publication_params[:news_source_snapshot_id],
          dry_run: false
        )
        summary_pub_result = pub_result

        unless pub_result.published?
          publication_failed = true
          raise ActiveRecord::Rollback
        end
      end

      update_attrs = bill_params.except(*vote_params)
      update_attrs = update_attrs.except(:summary) if summary_changed

      if @bill.update(update_attrs)
        create_vote(@bill)
        success = true
      else
        raise ActiveRecord::Rollback
      end
    end

    if summary_pub_result && publication_failed
      draft_rev = @bill.bill_summary_revisions.where(
        summary_markdown: summary_param,
        publication_role: "draft"
      ).order(:id).last

      snapshot = summary_pub_result.snapshot
      effective_snapshot = snapshot if snapshot && NewsArticleSourceSnapshot.exists?(snapshot.id)

      draft_rev ||= BillSummaryRevision.record_revision!(
        bill: @bill,
        summary_markdown: summary_param,
        actor: current_user,
        origin: "operator_edit",
        publication_role: "draft",
        review_state: "reviewed",
        news_source_snapshot: effective_snapshot
      )

      final_result = ManualNewsSummaryPublicationService::Result.new(
        status: summary_pub_result.status,
        errors: summary_pub_result.errors,
        reasons: summary_pub_result.reasons,
        revision: draft_rev,
        snapshot: effective_snapshot,
        grounding_result: summary_pub_result.grounding_result,
        eligibility_comparison: summary_pub_result.eligibility_comparison
      )

      return render_summary_publication_failure(final_result)
    end

    if success
      remove_audio(current_audio_path)
      # @lat: [[bootstrap-caching-and-rate-limiting#Why locale and featured bill are cached per locale]]
      [previous_sway_locale_id, @bill&.sway_locale_id].uniq.each do |locale_id|
        Api::V1::BootstrapController.expire_botm_cache(locale_id)
      end
      # @lat: [[bill-creator-shell#The Bill Creator shell#Why a bill save carries its own return tab#Summary saves own their success toast]]
      # @lat: [[mobile-bill-creator#Sections#The bill fields section]]
      respond_after_write(update_return_path, notice: update_success_notice, json: written_bill_json(@bill))
    else
      respond_after_write(update_return_path, errors: @bill.errors)
    end
  rescue ActiveRecord::RecordInvalid => e
    @bill.reload
    respond_after_write(update_return_path, errors: {base: e.message})
  end

  def destroy
    @bill&.destroy!
    # @lat: [[bootstrap-caching-and-rate-limiting#Why locale and featured bill are cached per locale]]
    Api::V1::BootstrapController.expire_botm_cache(@bill&.sway_locale_id)
    redirect_to new_bill_creator_path
  end

  def generate_summary
    case GenerateBillSummaryService.new(
      bill: @bill, actor: current_user,
      **supplemental_testimony_args, **summarization_model_arg,
      **reasoning_effort_arg
    ).call
    when :no_pipeline_data
      respond_after_write(summary_bill_creator_path(@bill), errors: {generation: "No pipeline data available"})
    when :unsupported_model
      # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
      respond_after_write(summary_bill_creator_path(@bill), errors: {generation: "That model is not one Sway offers. Reload the page and choose again."})
    when :unsupported_reasoning_effort
      respond_after_write(summary_bill_creator_path(@bill), errors: {generation: "That reasoning level is not supported. Choose default, low, medium, or high."})
    when :already_in_progress
      respond_after_write(summary_bill_creator_path(@bill), errors: {generation: "Generation already in progress"})
    when :enqueue_failed
      # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#A failed enqueue leaves a retry path]]
      respond_after_write(summary_bill_creator_path(@bill), errors: {generation: "The summary could not be queued. Try again."})
    else
      respond_after_write(summary_bill_creator_path(@bill))
    end
  end

  # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Supplemental testimony is replaced, never appended]]
  def supplemental_testimony
    UpdateSupplementalTestimonyService.new(
      bill: @bill, **supplemental_testimony_args
    ).call

    redirect_to positions_bill_creator_path(@bill)
  end

  # @lat: [[testimony-letters#How CleanAndGroupService orders and threads the cleaning steps#Manual stance overrides]]
  def testimony_letter_stance
    permitted = params.permit(:position, :stance, :excluded)
    position = Integer(permitted[:position], exception: false)
    stance = permitted[:stance].to_s.strip
    excluding = permitted[:excluded] == true || permitted[:excluded].to_s == "true"

    if position.nil? || position.negative? || (!excluding && !Testimony::StanceClassifier::STANCES.include?(stance))
      return render json: {error: "Invalid position or stance (expected support, oppose, or neutral)."}, status: :unprocessable_content
    end

    provisioning = @bill.bill_llm_provisioning
    cleaned = provisioning&.cleaned_testimony
    unless provisioning && cleaned.is_a?(Hash) && cleaned["letters"].is_a?(Array)
      return redirect_back_or_to(
        positions_bill_creator_path(@bill),
        inertia: {errors: {testimony_letter_stance: "No cleaned testimony letters available on this bill."}}
      )
    end

    updated = false
    provisioning.with_lock do
      artifact = provisioning.cleaned_testimony&.deep_dup
      next unless artifact.is_a?(Hash) && artifact["letters"].is_a?(Array)

      letters = artifact["letters"]
      target = letters.find { |letter| letter.is_a?(Hash) && Integer(letter["position"], exception: false) == position }
      if target
        if excluding
          target["excluded"] = true
        else
          target.delete("excluded")
          target["stance"] = stance
        end
        target["stance_override"] = true
        artifact["counts"] ||= {}
        active = letters.select { |l| l.is_a?(Hash) && l["excluded"] != true }
        artifact["counts"]["stance_support_count"] = active.count { |l| l["stance"] == "support" }
        artifact["counts"]["stance_oppose_count"] = active.count { |l| l["stance"] == "oppose" }
        artifact["counts"]["stance_neutral_count"] = active.count { |l| l["stance"] != "support" && l["stance"] != "oppose" }
        provisioning.update!(cleaned_testimony: artifact)
        updated = true
      end
    end

    unless updated
      return redirect_back_or_to(
        positions_bill_creator_path(@bill),
        inertia: {errors: {testimony_letter_stance: "Testimony letter not found."}}
      )
    end

    notice_msg = if excluding
      "Removed testimony letter from #{@bill.external_id}."
    else
      "Updated testimony letter stance to #{stance} on #{@bill.external_id}."
    end

    redirect_back_or_to positions_bill_creator_path(@bill),
      notice: notice_msg
  end

  # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Supplemental testimony is replaced, never appended]]
  # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Regeneration records its audit entry after enqueue]]
  def regenerate_summary
    case GenerateBillSummaryService.new(
      bill: @bill, actor: current_user, regenerate: true,
      **supplemental_testimony_args, **summarization_model_arg,
      **summary_instructions_arg, **reasoning_effort_arg
    ).call
    when :invalid_summary_instructions
      respond_after_write(summary_bill_creator_path(@bill), errors: {generation: "Instructions must be text up to 2,000 characters."})
    when :no_pipeline_data
      respond_after_write(summary_bill_creator_path(@bill), errors: {generation: "No pipeline data available for regeneration."})
    when :unsupported_model
      # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
      respond_after_write(summary_bill_creator_path(@bill), errors: {generation: "That model is not one Sway offers. Reload the page and choose again."})
    when :unsupported_reasoning_effort
      respond_after_write(summary_bill_creator_path(@bill), errors: {generation: "That reasoning level is not supported. Choose default, low, medium, or high."})
    when :already_in_progress
      respond_after_write(summary_bill_creator_path(@bill), errors: {generation: "Generation already in progress"})
    when :enqueue_failed
      respond_after_write(summary_bill_creator_path(@bill), errors: {generation: "The summary could not be queued. Try again."})
    else
      respond_after_write(summary_bill_creator_path(@bill), notice: "Summary regeneration queued successfully.")
    end
  end

  # @lat: [[organization-position-removal#Taking an organization's position off a bill#Approval wire values share one storage mapping]]
  def approve_org_position
    permitted = params.permit(:org_name, :support, :summary, :index, :draft_org_name,
      :draft_token, :claimed_affiliation_position, :override_private_individual)
    org_name = permitted[:org_name].to_s.strip

    case ApproveOrgPositionService.new(
      bill: @bill, actor: current_user,
      org_name: org_name, support: permitted[:support], summary: permitted[:summary].to_s,
      index: permitted[:index], draft_org_name: permitted[:draft_org_name],
      # @lat: [[bill-draft-org-position-controller#Bill draft organization-position controller#Draft identity separates a moved entry from a removed one]]
      draft_token: permitted[:draft_token],
      # @lat: [[bill-draft-org-position-controller#Bill draft organization-position controller#Draft identity separates a moved entry from a removed one]]
      claimed_affiliation_position: permitted[:claimed_affiliation_position],
      # @lat: [[private-individual-guard-override]]
      override_private_individual: permitted[:override_private_individual]
    ).call
    when :org_name_required
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "Organization name is required"}}
    when :summary_required
      # @lat: [[organization-position-removal#Taking an organization's position off a bill#A refusal reaches the operator as a message, not a 500]]
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "Summary is required"}}
    when :invalid_stance
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "Invalid stance (expected support|oppose|neutral)"}}
    when :identity_required
      # @lat: [[bill-draft-org-position-controller#Bill draft organization-position controller#Draft identity separates a moved entry from a removed one]]
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "This request did not say which draft to approve — send draft_token."}}
    when :draft_index_required
      # @lat: [[bill-draft-org-position-controller#Bill draft organization-position controller#Draft identity separates a moved entry from a removed one]]
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "This request named a draft but not its position — send index."}}
    when :draft_index_mismatch
      # @lat: [[bill-draft-org-position-controller#Bill draft organization-position controller#Draft identity separates a moved entry from a removed one]]
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: DraftOrgPositionRefusals::LIST_CHANGED}}
    when :evidence_retracted
      # @lat: [[hearing-testimony-census#What a hearings fetch can conclude#Retracting evidence retires the conclusions drawn from it]]
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "The testimony behind this draft was retracted — regenerate the " \
          "positions, or reject this draft."}}
    when :no_testimony
      # @lat: [[organization-position-removal#Taking an organization's position off a bill#A draft with no testimony behind it is not approvable]]
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "This bill has no testimony on file, so this draft cannot be " \
          "approved — paste the testimony back into Supplemental testimony, or reject this draft."}}
    when :run_in_flight
      # @lat: [[bill-creator-positions-tab#The Bill Creator positions tab#Why Approve says on this tab why it is off]]
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "A new summary is being written for this bill, and it will replace " \
          "these drafts when it finishes — wait for it to finish, then review and approve the new drafts."}}
    when :private_individual
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "This bill's testimony reads #{org_name} as a person writing for " \
          "themselves, not an organization — a resident who wrote in cannot be published as one.",
                           private_individual_refusal: true}}
    when :coverage_not_acknowledged
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "Some testimony did not reach the model — acknowledge what was left " \
          "out before publishing a position drawn from it."}}
    when :claimed_affiliation_not_found
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: DraftOrgPositionRefusals::LIST_CHANGED}}
    when :organization_has_users
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "This organization has registered user accounts on Sway and " \
          "manages its own positions — positions cannot be published on its behalf."}}
    when :approved
      flash[:notice] = "Approved #{org_name} on #{@bill.external_id}."
      redirect_to positions_bill_creator_path(@bill)
    else
      # @lat: [[bills-controller-design#Why approve_org_position names :approved explicitly and refuses unhandled outcomes]]
      SwayLogging.warn("approve_org_position.unhandled_outcome", bill_id: @bill.id)
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {org_position: "This position could not be approved. Reload and try again."}}
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Queue ownership outlives an operator stop]]
  def cancel_pipeline_run_bill
    run = LegislationPipelineRun.find(params[:id])
    back_path = pipeline_back_path(run.bill_id)
    if run.can_mark_cancelled?
      run.error_message = nil
      run.mark_cancelled!
      respond_after_write(back_path, status: :see_other, notice: "Pipeline run cancelled")
    else
      respond_after_write(back_path, status: :see_other, alert: "Cannot cancel run in status=#{run.status}")
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart]]
  def resume_pipeline_run
    run = LegislationPipelineRun.find(params[:id])
    back_path = pipeline_bill_creator_path(id: run.bill_id)

    enqueue_pipeline_run!(
      back_path: back_path,
      origin: "resume",
      notice: ->(new_run) { "Resume queued (run #{new_run.id})" }
    ) { LegislationPipelineRunService.new.resume(run, skip_enqueue: true) }
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Restart inherits the parent asset-download choice]]
  def restart_pipeline_run
    run = LegislationPipelineRun.find(params[:id])
    back_path = pipeline_bill_creator_path(id: run.bill_id)
    dma_param =
      if params.key?(:download_missing_assets)
        ActiveModel::Type::Boolean.new.cast(params[:download_missing_assets])
      end

    enqueue_pipeline_run!(
      back_path: back_path,
      origin: "restart",
      notice: ->(new_run) { "Restart queued (run #{new_run.id})" }
    ) { LegislationPipelineRunService.new.restart(run, download_missing_assets: dma_param, skip_enqueue: true) }
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  # @lat: [[legislation-pipeline#How a stage resolves its SwayLocale]]
  def run_pipeline
    stages_array = Array(params[:stages]) #: Array[untyped]
    stages = stages_array.map { |s| s.to_s }
    stages = stages.select { |s| PIPELINE_STAGE_KEYS.include?(s) }
    target_bill = params[:bill_id].present? ? Bill.find_by(id: params[:bill_id].to_i) : nil
    dma = ActiveModel::Type::Boolean.new.cast(params[:download_missing_assets])
    dma = true if dma.nil?
    if stages.include?("fetch-bills") && stages.include?("fetch-hearings")
      dma = true
    end
    back_path = pipeline_start_back_path(target_bill || params[:id], stages: stages, download_missing_assets: dma)

    sway_locale = nil
    if params[:sway_locale_id].present?
      sway_locale = SwayLocale.find_by(id: params[:sway_locale_id].to_i)
      if sway_locale.nil?
        return respond_after_write(back_path, errors: {pipeline: "Selected SwayLocale not found."})
      end
    end

    if target_bill
      if sway_locale && target_bill.sway_locale_id.present? && sway_locale.id != target_bill.sway_locale_id
        return respond_after_write(back_path, errors: {pipeline: "Single-bill pipeline run cannot override bill jurisdiction with a conflicting locale."})
      end
      sway_locale ||= target_bill.sway_locale
    elsif sway_locale.nil?
      return respond_after_write(back_path, errors: {pipeline: "A SwayLocale is required for all-bills pipeline runs."})
    end

    enqueue_pipeline_run!(
      back_path: back_path,
      origin: "fresh",
      notice: ->(created_run) { "Pipeline run #{created_run.id} queued (#{stages.size} stages)" }
    ) do
      LegislationPipelineRunService.new(
        stages: stages,
        bill: target_bill,
        sway_locale: sway_locale,
        download_missing_assets: dma
      ).call(skip_enqueue: true)
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Stuck runs require evidence of abandonment]]
  def sweep_stale_pipeline_runs
    back_path = pipeline_back_path(params[:id])

    rails_swept = 0

    ActiveRecord::Base.transaction do
      LegislationPipelineRun.abandoned_candidates.find_each do |run|
        run.with_lock do
          next unless run.abandoned? && run.can_force_fail?

          run.error_message = "Cleared by admin sweep"
          run.force_fail!
          rails_swept += 1
        end
      end
    end

    SwayLogging.info(
      "sweep_stale_pipeline_runs.done",
      rails_swept: rails_swept,
      user_id: current_user&.id
    )

    respond_after_write(
      back_path,
      notice: "Cleared #{rails_swept} stuck pipeline run#{"s" unless rails_swept == 1}.",
      json: {count: rails_swept}
    )
  end

  # @lat: [[paste-summary-dialog#Paste summary dialog#The dialog validates a pasted draft before publishing]]
  def paste_summary
    back_path = summary_bill_creator_path(id: @bill.id)

    outcome, errors = PasteSummaryService.new(
      bill: @bill, actor: current_user, summary_json: params[:summary_json]
    ).call

    unless [:persisted, :persisted_unsettled].include?(outcome)
      return render_paste_summary_errors(@bill, errors, back_path)
    end

    # @lat: [[bootstrap-caching-and-rate-limiting#Why locale and featured bill are cached per locale]]
    Api::V1::BootstrapController.expire_botm_cache(@bill.sway_locale_id)

    serialized_bill = paste_summary_bill_payload(@bill)
    if mobile_api_request?
      render json: {bill: serialized_bill}, status: :ok
    else
      flash[:paste_summary] = :persisted
      if outcome == :persisted_unsettled
        flash[:alert] = "Your summary was saved. The status on this bill was not updated — " \
          "paste it again to finish."
      end
      redirect_to back_path
    end
  end

  # @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
  def restore_summary_revision
    revision = @bill.bill_summary_revisions.find(params[:revision_id])

    if params[:expected_summary].present? && params[:expected_summary] != @bill.summary
      respond_after_write(summary_bill_creator_path(@bill), alert: STALE_SUMMARY_RESTORE_ALERT)
      return
    end

    # @type var result_rev: BillSummaryRevision?
    result_rev = nil
    @bill.with_lock do
      if params[:expected_summary].present? && params[:expected_summary] != @bill.summary
        respond_after_write(summary_bill_creator_path(@bill), alert: STALE_SUMMARY_RESTORE_ALERT)
        return
      end

      lock_provisioning = @bill.bill_llm_provisioning
      if lock_provisioning
        lock_provisioning.with_lock do
          result_rev = @bill.restore_summary_revision!(
            revision,
            actor: current_user,
            news_usage: params[:news_usage],
            source_uses: summary_publication_params[:source_uses]
          )
        end
      else
        result_rev = @bill.restore_summary_revision!(
          revision,
          actor: current_user,
          news_usage: params[:news_usage],
          source_uses: summary_publication_params[:source_uses]
        )
      end
    end

    # @lat: [[mobile-bill-creator#Sections#The summary revisions section]]
    json = restored_revision_json(result_rev)
    if result_rev&.publication_role == "draft"
      respond_after_write(summary_bill_creator_path(@bill, draft_revision_id: result_rev.id),
        json: json,
        notice: "Legacy revision restored as draft. Please review and declare news usage before publishing.")
    else
      # @lat: [[bootstrap-caching-and-rate-limiting#Why locale and featured bill are cached per locale]]
      Api::V1::BootstrapController.expire_botm_cache(@bill.sway_locale_id)
      respond_after_write(summary_bill_creator_path(@bill), json: json, notice: "Bill summary restored.")
    end
  end

  private

  def restored_revision_json(revision)
    return {} unless mobile_api_request? && revision

    {revision: BillSummaryRevisionResource.new(revision).serializable_hash}
  end

  def written_bill_json(bill)
    return {} unless mobile_api_request?

    BillResource.new(bill).serializable_hash
  end

  # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
  def summarization_model_arg
    value = params.permit(:summarization_model)[:summarization_model]
    {summarization_model: value.is_a?(::String) ? value : nil}
  end

  def reasoning_effort_arg
    value = params.permit(:reasoning_effort)[:reasoning_effort]
    {reasoning_effort: value.is_a?(::String) ? value : nil}
  end

  # @lat: [[bill-creator-summary-tab#Operator instructions for one regeneration]]
  def summary_instructions_arg
    return {} unless params.key?(:summary_instructions)

    raw = params[:summary_instructions]
    return {} if raw.nil?

    {summary_instructions: raw}
  end

  # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Supplemental testimony is replaced, never appended]]
  def supplemental_testimony_args
    permitted = params.permit(:supplemental_testimony, :clear_supplemental_testimony)
    {
      supplemental_testimony: permitted[:supplemental_testimony],
      clear_supplemental_testimony: ActiveModel::Type::Boolean.new.cast(
        permitted[:clear_supplemental_testimony]
      ) || false
    }
  end

  # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
  def bills_sort_param
    params.key?(:bills_sort) ? params[:bills_sort] : params[:sort]
  end

  # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
  def bills_direction_param
    params.key?(:bills_direction) ? params[:bills_direction] : params[:direction]
  end

  # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
  def bills_page_param
    params.key?(:bills_page) ? params[:bills_page] : params[:page]
  end

  # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
  def bills_search_param
    params.key?(:bills_search) ? params[:bills_search] : params[:search]
  end

  # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
  def bills_legislative_session_id_param
    params.key?(:bills_legislative_session_id) ? params[:bills_legislative_session_id] : params[:legislative_session_id]
  end

  def requested_legislative_session
    return @requested_legislative_session if defined?(@requested_legislative_session)

    sway_locale = current_sway_locale
    if sway_locale.nil?
      @requested_legislative_session = nil
      return nil
    end

    raw_id = bills_legislative_session_id_param.presence
    @requested_legislative_session =
      raw_id ? sway_locale.legislative_sessions.find_by(id: raw_id) : nil
  end

  def past_bills_of_the_month?
    action_name == "past_of_the_month"
  end

  def bills_list_mode
    past_bills_of_the_month? ? "past_bills_of_the_month" : "all_bills"
  end

  def legislative_sessions_prop
    return [] if current_sway_locale.nil? || past_bills_of_the_month?

    LegislativeSessionResource.new(
      current_sway_locale.legislative_sessions.order(start_date: :desc, id: :desc)
    ).serializable_hash
  end

  def selected_legislative_session_id_prop
    return nil if current_sway_locale.nil? || past_bills_of_the_month?

    (requested_legislative_session || current_sway_locale.current_legislative_session)&.id
  end

  # @lat: [[bills-controller-design#BillsController design#The web bills index grows a stable page window#The count and list share one scoped query]]
  def bills_index_scope
    return Bill.none if current_sway_locale.nil?

    scope =
      if past_bills_of_the_month?
        Bill.past_of_the_month(sway_locale: current_sway_locale)
      elsif (session = requested_legislative_session)
        Bill.for_legislative_session(session)
      else
        Bill.current_session(current_sway_locale).where(sway_locale: current_sway_locale)
      end

    # @lat: [[bills-controller-design#BillsController design#The web bills index grows a stable page window#Search treats wildcard characters as text]]
    search_term = bills_search_param
    if search_term.present?
      escaped_search = ActiveRecord::Base.sanitize_sql_like(search_term.to_s)
      scope = scope.where("title LIKE ? ESCAPE '\\'", "%#{escaped_search}%")
    end

    scope
  end

  def pipeline_back_path(bill_or_id = nil)
    id = bill_or_id.respond_to?(:id) ? bill_or_id.id : bill_or_id
    if id.present?
      pipeline_bill_creator_path(id: id.to_i)
    else
      new_bill_creator_path(bill_creator_tab: :pipeline)
    end
  end

  # @lat: [[bill-creator-shell#The Bill Creator shell#Why the Bill Creator carries query parameters across navigation]]
  def pipeline_start_back_path(bill_or_id, stages:, download_missing_assets:)
    target = URI.parse(pipeline_back_path(bill_or_id))
    source = referer_uri
    source_query = (source&.path == target.path) ? source&.query : target.query
    query = URI.decode_www_form(source_query.to_s)
    query.reject! do |key, _|
      %w[
        selected_stages selected_stages[] stages stages[]
        download_missing_assets download_missing_assets[] bill_creator_tab tab_key
      ].include?(key)
    end
    query << ["bill_creator_tab", "pipeline"] if bill_or_id.blank?
    query << ["selected_stages", stages.join(",")]
    query << ["download_missing_assets", download_missing_assets ? "1" : "0"]
    target.query = URI.encode_www_form(query)
    target.to_s
  end

  # @lat: [[bills-controller-design#enqueue_pipeline_run! and render_pipeline_duplicate_run]]
  def render_pipeline_duplicate_run(existing, back_path, flash_message: nil)
    existing_id = existing&.id
    message = flash_message || "Pipeline already running (run ##{existing_id})"
    if mobile_api_request?
      render_error(
        code: "duplicate_run",
        message: message,
        status: :conflict,
        details: {existing_run_id: existing_id}
      )
    else
      flash[:alert] = message
      redirect_to back_path
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Request admission blocks every active run]]
  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#An enqueue failure keeps the run and marks it failed]]
  def enqueue_pipeline_run!(back_path:, origin:, notice:)
    # @type var run: LegislationPipelineRun?
    run = nil
    # @type var existing: LegislationPipelineRun?
    existing = nil
    begin
      ActiveRecord::Base.transaction(requires_new: true) do
        existing = LegislationPipelineRun.active_any.first
        run = existing ? nil : yield
      end
    rescue LegislationPipelineRunService::ResumeNotAllowed,
      LegislationPipelineRunService::StageAllowlistError,
      LegislationPipelineRunService::LocaleError => e
      return respond_after_write(back_path, errors: {pipeline: e.message})
    end

    return render_pipeline_duplicate_run(existing, back_path) if existing

    # @lat: [[rbs-signatures#RBS signatures]]
    created_run = run
    return unless created_run

    begin
      RunLegislationPipelineJob.perform_later(created_run.id, origin: origin)
      respond_after_write(back_path, notice: notice.call(created_run))
    rescue ActiveJob::EnqueueError => e
      if created_run.persisted?
        created_run.update!(error_message: "enqueue failed: #{e.message[0, 200]}")
        created_run.mark_failed! if created_run.can_mark_failed?
      end
      render_pipeline_duplicate_run(LegislationPipelineRun.active_any.first, back_path, flash_message: e.message)
    end
  end

  # @lat: [[paste-summary-dialog#Paste summary dialog#The rejected payload leaves the published summary unchanged]]
  def render_paste_summary_errors(bill, errors, back_path)
    if mobile_api_request?
      render_error(
        code: "validation_failed",
        message: "Summary validation failed.",
        status: :unprocessable_content,
        details: {errors: errors}
      )
    else
      flash[:paste_summary_errors] = errors.map do |er|
        {path: er[:path].to_s, message: er[:message].to_s}
      end
      redirect_to back_path
    end
  end

  # @lat: [[paste-summary-dialog#Paste summary dialog#The dialog validates a pasted draft before publishing]]
  def paste_summary_bill_payload(bill)
    provisioning = bill.bill_llm_provisioning
    {
      id: bill.id,
      external_id: bill.external_id,
      bill_llm_provisioning: provisioning&.to_sway_json
    }
  end

  # @lat: [[mobile-bill-creator#Each tab gets only its own props]]
  def mobile_bill_creator_tab_props(props)
    return props unless mobile_api_request?

    props.merge(legislation_pipeline_run_props).slice(*BILL_CREATOR_TAB_PROPS.fetch(bill_creator_tab_param.to_s, BILL_PICKER_PROPS))
  end

  # @lat: [[lazy-inertia-props#Why the props became callables]]
  def bill_creator_props
    {
      bills: -> { picker_bills(Bill.where(sway_locale: current_sway_locale).order(introduced_date_time_utc: :desc, external_id: :desc)) },
      bill: -> {
        @bill.to_sway_json.tap do |b|
          # @lat: [[query-plan-indexes#Index shapes the query planner can use#A query-cost guard measures growth, not a ceiling]]
          b[:organizations] = @bill.organizations
            .with_attached_icon
            .includes(organization_bill_positions: :bill)
            .map(&:to_sway_json)
          b[:bill_llm_provisioning] = @bill.bill_llm_provisioning&.to_sway_json
          # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Bill refresh uses every active status]]
          b[:bill_pipeline_refresh] = LegislationPipelineRun.active_for_bill(@bill).order(created_at: :desc).first&.to_builder&.attributes!
          # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Which run the Bill Creator surfaces#The failed-run alert links to its own run]]
          b[:bill_pipeline_last_failure] = last_failed_pipeline_run_summary
          # @lat: [[lazy-inertia-props#Sorting a loaded association in Ruby]]
          b[:override_categories] = @bill.categories.sort_by(&:name).map { |c| {id: c.id, name: c.name, active: c.active} }
        end
      },
      **summary_prompt_prop,
      # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
      summary_model_options: -> { summary_model_options },
      current_summarization_model: -> { admin_setting_for_creator.summarization_model },
      current_summarization_reasoning_effort: -> { admin_setting_for_creator.summarization_reasoning_effort },
      **testimony_campaign_letters_prop,
      **public_testimony_letters_prop,
      **testimony_report_props,
      # @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
      summary_sources: -> { SummarySourcesResource.new(SummarySourcesReport.call(bill: @bill)).serializable_hash },
      **summary_source_documents_prop,
      **summary_revisions_prop,
      # @lat: [[bills-controller-design#BillsController design#The Bill Creator separates category choices from override records]]
      active_categories: -> { Category.where(active: true).order(:name).map { |c| {id: c.id, name: c.name} } },
      # @lat: [[bills-controller-design#BillsController design#The Bill Creator separates category choices from override records]]
      max_active_categories_per_bill: -> { Category::MAX_ACTIVE_PER_BILL },
      legislators: -> { vote_entry_legislators },
      legislator_votes: -> { @bill.legislator_votes.map(&:to_sway_json) },
      # @lat: [[query-plan-indexes#Index shapes the query planner can use#A query-cost guard measures growth, not a ceiling]]
      organizations: -> {
        Organization
          .with_attached_icon
          .includes(organization_bill_positions: :bill)
          .where(sway_locale: @bill&.sway_locale || current_sway_locale)
          .map(&:to_sway_json)
      },
      tab_key: -> { bill_creator_tab_param },
      pipeline_preview: -> { pipeline_preview_for(@bill) },
      # @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#The page's control props follow URL precedence]]
      **pipeline_controls_state,
      legislator_votes_refreshed_at: -> { legislator_votes_refresh_toast&.[](:refreshed_at) },
      legislator_votes_source: -> { legislator_votes_refresh_toast&.[](:source) },
      news_articles: -> {
        if @bill&.persisted?
          articles = @bill.bill_news_articles
            .includes(:news_article, :current_text_version, :approved_by, :stance_by)
            .order(created_at: :desc)
          AdminBillNewsArticleResource.new(articles).serializable_hash
        else
          []
        end
      },
      receipt_status: -> {
        if @bill&.persisted?
          @bill.news_article_discovery_requests.order(created_at: :desc, id: :desc).pick(:status)
        end
      },
      review_draft_revision: -> {
        if params[:draft_revision_id].present? && @bill&.persisted?
          draft = @bill.bill_summary_revisions.find_by(id: params[:draft_revision_id])
          draft ? BillSummaryRevisionResource.new(draft).serializable_hash : nil
        end
      }
    }
  end

  def admin_setting_for_creator
    @admin_setting_for_creator ||= AdminSetting.singleton
  end

  # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
  def summary_model_options(catalog_models: nil, decision_catalog_models: nil)
    catalog = catalog_models || begin
      Llm::OpenRouterModelsService.call
    rescue => e
      Rails.logger.warn("BillsController#summary_model_options failed to load catalog models: #{e.class}: #{e.message}")
      []
    end
    decision_catalog = decision_catalog_models || begin
      Llm::OpenRouterModelsService.decision_models
    rescue => e
      Rails.logger.warn("BillsController#summary_model_options failed to load decision catalog models: #{e.class}: #{e.message}")
      []
    end
    setting = admin_setting_for_creator
    offered = setting.offered_models_list(
      catalog_models: catalog,
      decision_catalog_models: decision_catalog
    )
    labels = AdminSetting.offered_model_labels(
      catalog_models: catalog,
      decision_catalog_models: decision_catalog,
      setting: setting,
      precomputed_offered_models: offered
    )
    offered.map do |model|
      {
        id: model,
        label: labels.fetch(model, model),
        supports_reasoning: Llm::ModelCatalog.supports_reasoning?(model, catalog_models: catalog)
      }
    end
  end

  # @lat: [[lazy-inertia-props#Lazy Inertia props#Current optional and deferred JSON props]]
  def summary_prompt_prop
    # @lat: [[mobile-bill-creator#Sections#The summary generation section#Preparing the summary prompt]]
    if mobile_api_request?
      return {} unless params[:summary_prompt] == "1"

      return {summary_prompt: -> { BillSummaryPromptBuilder.new(@bill).call }}
    end

    {summary_prompt: InertiaRails.optional { BillSummaryPromptBuilder.new(@bill).call }}
  end

  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  def summary_source_documents_prop
    # @lat: [[mobile-bill-creator#Sections#The summary sources section]]
    if mobile_api_request?
      return {} unless params[:summary_source_documents] == "1"

      return {summary_source_documents: -> { summary_source_documents_json }}
    end

    {summary_source_documents: InertiaRails.optional { summary_source_documents_json }}
  end

  def summary_source_documents_json
    SummarySourceDocumentsResource.new(SummarySourceDocuments.call(bill: @bill)).serializable_hash
  end

  # @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
  def summary_revisions_prop
    # @lat: [[mobile-bill-creator#Sections#The summary revisions section]]
    if mobile_api_request?
      return {} unless params[:summary_revisions] == "1"

      return {summary_revisions: -> { summary_revisions_json }}
    end

    {summary_revisions: InertiaRails.optional { summary_revisions_json }}
  end

  def summary_revisions_json
    return [] unless @bill&.persisted?

    BillSummaryRevisionResource.new(
      @bill.bill_summary_revisions.order(created_at: :desc, id: :desc)
    ).serializable_hash
  end

  # @lat: [[campaign-letter-disclosure#Why the letter text is a prop of its own]]
  def testimony_campaign_letters_prop
    return {} if mobile_api_request?

    {
      testimony_campaign_letters: InertiaRails.optional {
        TestimonyCampaignLettersResource.new(
          cleaned_testimony_derivation[:campaign_drafts],
          params: {
            letters_by_position: cleaned_testimony_derivation[:letters_by_position],
            full_text: cleaned_testimony_derivation[:full_text]
          }
        ).serializable_hash
      }
    }
  end

  def public_testimony_letters_prop
    return {} if mobile_api_request?

    {
      public_testimony_letters: InertiaRails.optional {
        PublicTestimonyLetterResource.new(browsable_testimony_entries).serializable_hash
      }
    }
  end

  def testimony_report_props
    {
      campaign_organization_candidates: -> { campaign_organization_candidates(testimony_report_campaigns) },
      testimony_coverage: -> { TestimonyCoverageResource.new(Testimony::CoverageReport.call(bill: @bill)).serializable_hash },
      testimony_campaign_drafts: -> {
        TestimonyCampaignDraftResource.new(
          cleaned_testimony_derivation[:campaign_drafts],
          params: {
            # @lat: [[campaign-approval#Approving a campaign from a testimony draft#A draft's identity is its content, not its position]]
            rejected_hashes: @bill.bill_llm_provisioning&.rejected_campaign_draft_hash_list || [],
            individual_hashes: @bill.bill_llm_provisioning&.individual_campaign_draft_hash_list || []
          }
        ).serializable_hash
      },
      testimony_claimed_affiliations: -> { TestimonyClaimedAffiliationResource.new(cleaned_testimony_derivation[:claimed_letters]).serializable_hash },
      sending_service_domains: -> { SendingServiceDomainResource.new(testimony_report_panel_domains.panel_ranked).serializable_hash },
      sending_service_domains_total: -> { testimony_report_panel_domains.count },
      campaigns: -> { CampaignResource.new(testimony_report_campaigns).serializable_hash },
      public_testimony_counts: -> { Testimony::BrowsableLetters.counts_from_entries(browsable_testimony_entries) }
    }
  end

  def browsable_testimony_entries
    @browsable_testimony_entries ||= Testimony::BrowsableLetters.for_bill(@bill)
  end

  def testimony_report_campaigns
    @testimony_report_campaigns ||= @bill.campaigns.includes(:organization).order(:id)
  end

  def testimony_report_panel_domains
    @testimony_report_panel_domains ||= SendingServiceDomain.for_panel
  end

  def cleaned_testimony_derivation
    @cleaned_testimony_derivation ||= compute_cleaned_testimony_derivation
  end

  def compute_cleaned_testimony_derivation
    artifact = @bill.bill_llm_provisioning&.cleaned_testimony
    letters = artifact.is_a?(Hash) ? artifact.fetch("letters", []) : []
    {
      campaign_drafts: artifact.is_a?(Hash) ? artifact.fetch("campaign_drafts", []) : [],
      letters_by_position: letters.index_by { |letter| letter["position"] },
      full_text: artifact.is_a?(Hash) ? artifact.fetch("text", "").to_s : "",
      claimed_letters: letters.select { |letter| letter["source_kind"] == "person_speaking_for_org" && letter["excluded"] != true }
    }
  end

  # @lat: [[campaign-approval#Approving a campaign from a testimony draft#An organization link carries the decision that made it]]
  def campaign_organization_candidates(campaigns)
    Campaigns::OrganizationCandidatesService
      .call_all(bill: @bill, campaigns: campaigns)
      .transform_values { |candidates| CampaignOrganizationCandidateResource.new(candidates).serializable_hash }
  end

  def last_failed_pipeline_run_summary
    run = LegislationPipelineRun.where(bill_id: @bill.id, status: "failed")
      .order(created_at: :desc).first
    return nil if run.nil?

    {run_id: run.id, error_message: run.error_message.to_s, failed_at: run.updated_at.iso8601}
  end

  # @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#The page's control props follow URL precedence]]
  PIPELINE_STAGE_KEYS = %w[fetch-bills fetch-law extract-text parse-sections generate-diffs fetch-hearings clean-testimony summarize-bill].freeze

  # @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#The page's control props follow URL precedence]]
  DEFAULT_PIPELINE_STAGE_KEYS = (PIPELINE_STAGE_KEYS - %w[summarize-bill]).freeze

  # @lat: [[lazy-inertia-props#Lazy Inertia props#Why shared work sits behind memoized methods]]
  def pipeline_controls_state
    @pipeline_controls_state ||= compute_pipeline_controls_state
  end

  # @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#Why an empty stage selection is spelled out on the wire]]
  def requested_stage_names
    raw = params[:selected_stages] || params[:stages]
    case raw
    when Array then raw.map(&:to_s)
    when String then raw.split(",").map(&:strip).reject(&:empty?)
    end
  end

  # @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#The page's control props follow URL precedence]]
  def selected_pipeline_stages
    named = requested_stage_names
    return DEFAULT_PIPELINE_STAGE_KEYS.dup if named.nil?

    named.select { |name| PIPELINE_STAGE_KEYS.include?(name) }
  end

  def compute_pipeline_controls_state
    selected = selected_pipeline_stages

    # @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#The page's control props follow URL precedence]]
    bill_id = (params[:id].presence || params[:bill_id]).to_s
    # @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#The page's control props follow URL precedence]]
    dma_raw = params[:download_missing_assets]
    dma = dma_raw.nil? || ActiveModel::Type::Boolean.new.cast(dma_raw)
    dma = true if dma.nil?
    {
      selected_stages: selected,
      bill_id: bill_id,
      download_missing_assets: dma
    }
  end

  # @lat: [[bills-controller-design#pipeline_controls_state and pipeline_preview_for]]
  def pipeline_preview_for(bill)
    stages_array = requested_stage_names || []
    return nil if stages_array.empty?

    # @lat: [[legislation-pipeline#The legislation pipeline#The stage graph]]
    state = pipeline_controls_state
    bills_relation =
      if bill
        Bill.where(id: bill.id)
      else
        Bill.where(sway_locale: current_sway_locale)
      end

    PipelinePreviewService.fetch(
      stages: stages_array,
      download_missing_assets: state[:download_missing_assets],
      bills: bills_relation
    )
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#The vote-entry roster is everyone who ever held the seat#The displayed term needs its own district preload]]
  def vote_entry_legislators
    locale = @bill&.sway_locale || current_sway_locale
    return [] if locale.nil?

    roster = locale
      .legislators(false)
      .joins(:legislator_terms)
      .with_term_history
      .distinct
      .to_a

    roster = roster.reject { |l| senate_only_excluded?(l) } if nomination_bill?(locale)

    LegislatorResource.new(roster).serializable_hash
  end

  def nomination_bill?(locale)
    locale.congress? && @bill&.external_id.to_s.starts_with?("PN")
  end

  def senate_only_excluded?(legislator)
    LegislatorResource.display_term(legislator)&.title&.starts_with?("Rep") || false
  end

  # @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
  def picker_bills(scope)
    BillCreator::PickerBillsSerializer.call(scope, locale: current_sway_locale)
  end

  def legislator_votes_refresh_toast
    return @legislator_votes_refresh_toast if defined?(@legislator_votes_refresh_toast)

    @legislator_votes_refresh_toast = legislator_votes_refresh_toast_for(@bill)
  end

  # @lat: [[client-caches-and-identity#Client caches and identity#Why last-seen state moved off the cookie#The refresh notice compares one vote timestamp]]
  def legislator_votes_refresh_toast_for(bill)
    return nil unless current_user&.is_sway_admin?

    view = AdminBillView.find_or_initialize_by(admin_user_id: current_user.id, bill_id: bill.id)
    last_seen = view.last_seen_at
    most_recent = LegislatorVote.where(bill_id: bill.id)
      .where.not(source: "manual")
      .maximum(:updated_at)

    # @lat: [[client-caches-and-identity#Client caches and identity#Why last-seen state moved off the cookie#The refresh notice compares one vote timestamp]]
    # @type var payload: {refreshed_at: String, source: String}?
    payload =
      if most_recent.nil? || (last_seen && last_seen >= most_recent)
        nil
      else
        source = LegislatorVote.where(bill_id: bill.id, updated_at: most_recent)
          .where.not(source: "manual")
          .pick(:source)
          .to_s
        {
          # @lat: [[client-caches-and-identity#Client caches and identity#Why last-seen state moved off the cookie#The refresh notice compares one vote timestamp]]
          refreshed_at: most_recent
            .in_time_zone(bill.sway_locale.time_zone.presence || "Eastern Time (US & Canada)")
            .strftime("%H:%M").to_s,
          source: source
        }
      end

    # @lat: [[client-caches-and-identity#Client caches and identity#Why last-seen state moved off the cookie#The refresh notice compares one vote timestamp]]
    if payload || view.new_record?
      view.last_seen_at = Time.zone.now
      view.save!
    end
    payload
  end

  def activity_log_entries_prop
    @activity_log_entries_prop ||= BillCreator::ActivityLogPage.call(
      bill: @bill,
      subject: params[:subject],
      severity: params[:severity],
      window: params[:window],
      cursor: params[:cursor]
    )
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
      when "past_of_the_month"
        if current_sway_locale.present?
          "#{current_sway_locale&.human_name} Past Bills of the Month"
        else
          "Sway Past Bills of the Month"
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

  def set_bill_for_show
    @bill =
      Bill.unscope(where: :archived_at).includes(
        :legislator,
        :sway_locale
      ).find(params[:id])
  end

  def set_bill
    @bill =
      Bill.includes(
        :legislator_votes,
        :legislator,
        :sway_locale,
        :bill_llm_provisioning
      ).find(params[:id])
  end

  def remove_audio(audio_path)
    return unless @bill.present? && @bill.audio_bucket_path != audio_path

    delete_file(
      bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS],
      file_name: audio_path
    )
  end

  def create_vote(b)
    unless bill_params[:house_roll_call_vote_number] ||
        bill_params[:senate_roll_call_vote_number]
      return
    end

    # @lat: [[bills-controller-roll-calls#In-place roll-call update and purging]]
    vote = b.roll_calls.max_by(&:id) || RollCall.new(bill_id: b.id)
    vote.assign_attributes(
      house_roll_call_vote_number: bill_params[:house_roll_call_vote_number],
      senate_roll_call_vote_number: bill_params[:senate_roll_call_vote_number]
    )
    # @lat: [[bills-controller-roll-calls#Re-fetching legislator votes after roll-call correction]]
    refetch_legislator_votes = vote.persisted? &&
      (vote.house_roll_call_vote_number_changed? || vote.senate_roll_call_vote_number_changed?)
    vote.save!
    b.roll_calls.where.not(id: vote.id).destroy_all
    LegislatorVoteFetchJob.perform_later(b.id) if refetch_legislator_votes
  end

  # @lat: [[bill-creator-shell#The Bill Creator shell#Why a bill save carries its own return tab]]
  def update_return_path
    if saved_from_summary_tab?
      summary_bill_creator_path(@bill.id)
    else
      creator_bill_creator_path(@bill.id, {event_key: "legislator_votes"})
    end
  end

  # @lat: [[bill-creator-shell#The Bill Creator shell#Why a bill save carries its own return tab#Summary saves own their success toast]]
  def update_success_notice
    return if saved_from_summary_tab?

    "Bill Updated"
  end

  # @lat: [[bill-creator-shell#The Bill Creator shell#Why a bill save carries its own return tab]]
  def saved_from_summary_tab?
    params[:return_tab].to_s == "summary"
  end

  def bill_params
    params.transform_keys { |key| key.to_s.underscore }.permit(
      :external_id,
      :external_version,
      :title,
      :link,
      :chamber,
      :introduced_date_time_utc,
      :house_vote_date_time_utc,
      :senate_vote_date_time_utc,
      # @lat: [[bills-category-filter#Bills category filter#The single-subject category column is retired]]
      :summary,
      :status,
      :active,
      :audio_bucket_path,
      :audio_by_line,
      :sway_locale_id,
      :legislator_id,
      :house_roll_call_vote_number,
      :senate_roll_call_vote_number
    )
  end

  def vote_params
    %i[house_roll_call_vote_number senate_roll_call_vote_number]
  end

  def summary_publication_params
    params.permit(
      :news_usage,
      :news_source_snapshot_id,
      source_uses: [
        :bill_news_article_id,
        :text_version_id,
        :claim_text,
        :evidence_excerpt,
        :citation_url
      ]
    )
  end

  def render_summary_publication_failure(result)
    if mobile_api_request?
      render json: {
        error: {
          code: "validation_failed",
          message: "Manual summary publication failed validation.",
          details: {
            status: result.status,
            errors: result.errors
          }
        }
      }, status: :unprocessable_content
    else
      redirect_to update_return_path,
        inertia: {
          errors: {
            summary: result.errors.first || "Manual summary publication failed validation",
            news_usage: result.errors.first
          }
        }
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
          :icon_url,
          :icon_signed_id,
          positions: %i[id bill_id summary support]
        )
      end
  end
end
