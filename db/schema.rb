# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_24_171428) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.string "city", null: false
    t.string "country", default: "US", null: false
    t.datetime "created_at", null: false
    t.string "latitude"
    t.string "longitude"
    t.string "postal_code", null: false
    t.string "region_code", null: false
    t.string "street", null: false
    t.string "street2"
    t.string "street3"
    t.datetime "updated_at", null: false
    t.string "normalized_key"
    t.json "place_types", default: [], null: false
    t.datetime "geocode_next_attempt_at"
    t.datetime "geocode_abandoned_at"
    t.index ["normalized_key"], name: "index_addresses_on_normalized_key"
  end

  create_table "admin_bill_views", force: :cascade do |t|
    t.integer "admin_user_id", null: false
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id", "bill_id"], name: "index_admin_bill_views_on_admin_user_and_bill", unique: true
    t.index ["bill_id"], name: "index_admin_bill_views_on_bill_id"
  end

  create_table "admin_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "summarization_model", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
    t.string "classification_model", default: "claude-haiku-4-5-20251001", null: false
    t.integer "summary_batch_chunk_size", default: 25, null: false
    t.boolean "summary_batch_enabled", default: false, null: false
    t.json "offered_models"
    t.string "summarization_reasoning_effort"
    t.string "classification_reasoning_effort"
    t.string "decision_model", default: "ScaleDown Classify Latest", null: false
    t.string "extraction_model", default: "ScaleDown Extract Latest", null: false
    t.index ["updated_by_id"], name: "index_admin_settings_on_updated_by_id"
  end

  create_table "api_keys", force: :cascade do |t|
    t.integer "bearer_id", null: false
    t.string "bearer_type", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_on_utc"
    t.string "name"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_device_id"
    t.index ["bearer_id", "bearer_type"], name: "index_api_keys_on_bearer_id_and_bearer_type"
    t.index ["expires_at"], name: "index_api_keys_on_expires_at"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["user_device_id"], name: "index_api_keys_on_user_device_id"
  end

  create_table "article_bills", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.integer "organization_id", null: false
    t.string "partner_slug", null: false
    t.string "article_url", null: false
    t.string "article_title", null: false
    t.datetime "published_at"
    t.integer "clicks_count", default: 0, null: false
    t.integer "registrations_count", default: 0, null: false
    t.integer "votes_count", default: 0, null: false
    t.integer "pro_votes_count", default: 0, null: false
    t.integer "con_votes_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id", "article_url"], name: "index_article_bills_on_bill_id_and_article_url", unique: true
    t.index ["bill_id"], name: "index_article_bills_on_bill_id"
    t.index ["organization_id", "published_at"], name: "index_article_bills_on_organization_id_and_published_at"
    t.index ["organization_id"], name: "index_article_bills_on_organization_id"
    t.index ["partner_slug", "bill_id"], name: "index_article_bills_on_partner_slug_and_bill_id"
  end

  create_table "bill_amendment_operations", force: :cascade do |t|
    t.text "anchor_text"
    t.integer "bill_id", null: false
    t.integer "bill_section_reference_id"
    t.integer "char_end", default: -1, null: false
    t.integer "char_start", default: -1, null: false
    t.datetime "created_at", null: false
    t.integer "operation", null: false
    t.integer "ordinal", null: false
    t.text "replacement_text"
    t.integer "source", default: 0, null: false
    t.integer "target_law_section_id"
    t.datetime "updated_at", null: false
    t.index ["bill_id", "ordinal"], name: "idx_bill_amendment_ops_on_bill_ordinal"
    t.index ["bill_id"], name: "index_bill_amendment_operations_on_bill_id"
    t.index ["bill_section_reference_id"], name: "index_bill_amendment_operations_on_bill_section_reference_id"
    t.index ["target_law_section_id"], name: "index_bill_amendment_operations_on_target_law_section_id"
  end

  create_table "bill_categories", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.integer "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id", "category_id"], name: "index_bill_categories_on_bill_id_and_category_id", unique: true
    t.index ["category_id"], name: "index_bill_categories_on_category_id"
  end

  create_table "bill_cosponsors", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.integer "legislator_id", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_bill_cosponsors_on_bill_id"
    t.index ["legislator_id"], name: "index_bill_cosponsors_on_legislator_id"
  end

  create_table "bill_interesting_scores", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.datetime "computed_at", null: false
    t.datetime "created_at", null: false
    t.float "normalized_score", null: false
    t.float "raw_score", null: false
    t.text "signals", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id", "id"], name: "index_bill_interesting_scores_on_bill_id_and_id"
  end

  create_table "bill_llm_provisionings", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.text "diff_content"
    t.datetime "diff_generated_at"
    t.text "draft_org_positions"
    t.text "generation_error"
    t.string "generation_status"
    t.datetime "hearings_fetched_at"
    t.text "llm_full_breakdown"
    t.datetime "llm_generated_at"
    t.string "llm_model"
    t.string "llm_provider"
    t.text "llm_summary"
    t.string "summary_run_id"
    t.text "supplemental_testimony"
    t.datetime "updated_at", null: false
    t.text "extracted_testimony"
    t.datetime "testimony_fetched_at"
    t.text "testimony_attachments"
    t.boolean "citations_valid"
    t.text "invalid_citations"
    t.datetime "categories_unmatched_at"
    t.text "cleaned_testimony"
    t.datetime "cleaned_testimony_at"
    t.text "rejected_campaign_draft_hashes"
    t.string "summary_batch_id"
    t.datetime "summary_batch_expires_at"
    t.string "summary_batch_testimony_digest"
    t.text "news_articles"
    t.datetime "news_articles_fetched_at"
    t.boolean "news_urls_valid"
    t.text "invalid_news_urls"
    t.text "individual_campaign_draft_hashes"
    t.index ["bill_id"], name: "index_bill_llm_provisionings_on_bill_id", unique: true
    t.index ["categories_unmatched_at"], name: "index_bill_llm_provisionings_on_categories_unmatched_at", where: "categories_unmatched_at IS NOT NULL"
    t.index ["llm_generated_at"], name: "index_bill_llm_provisionings_on_llm_generated_at"
    t.index ["summary_batch_id"], name: "index_bill_llm_provisionings_on_summary_batch_id"
    t.index ["summary_run_id"], name: "index_bill_llm_provisionings_on_summary_run_id", unique: true, where: "summary_run_id IS NOT NULL"
  end

  create_table "bill_news_articles", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.integer "news_article_id", null: false
    t.string "match_kind", default: "direct", null: false
    t.text "match_evidence"
    t.boolean "approved", default: false, null: false
    t.integer "approved_by_id"
    t.datetime "approved_at"
    t.integer "review_version", default: 0, null: false
    t.string "stance"
    t.integer "stance_by_id"
    t.integer "stance_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "current_text_version_id"
    t.index ["approved_by_id"], name: "index_bill_news_articles_on_approved_by_id"
    t.index ["bill_id", "approved"], name: "index_bill_news_articles_on_bill_id_and_approved"
    t.index ["bill_id", "news_article_id"], name: "index_bill_news_articles_on_bill_id_and_news_article_id", unique: true
    t.index ["bill_id"], name: "index_bill_news_articles_on_bill_id"
    t.index ["current_text_version_id"], name: "index_bill_news_articles_on_current_text_version_id"
    t.index ["news_article_id"], name: "index_bill_news_articles_on_news_article_id"
    t.index ["stance_by_id"], name: "index_bill_news_articles_on_stance_by_id"
  end

  create_table "bill_notifications", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_bill_notifications_on_bill_id", unique: true
  end

  create_table "bill_score_districts", force: :cascade do |t|
    t.integer "against", default: 0, null: false
    t.integer "bill_score_id", null: false
    t.datetime "created_at", null: false
    t.integer "district_id", null: false
    t.integer "for", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["bill_score_id", "district_id"], name: "index_bill_score_districts_on_bs_and_district", unique: true
    t.index ["district_id"], name: "index_bill_score_districts_on_district_id"
  end

  create_table "bill_scores", force: :cascade do |t|
    t.integer "against", default: 0, null: false
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.integer "for", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_bill_scores_on_bill_id", unique: true
  end

  create_table "bill_section_references", force: :cascade do |t|
    t.text "anchor"
    t.string "article", null: false
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.integer "fuzzy_score"
    t.string "key", null: false
    t.integer "ordinal", null: false
    t.integer "resolution", default: 2, null: false
    t.string "section", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.boolean "authoritative", default: false, null: false
    t.index ["bill_id", "ordinal"], name: "idx_bill_section_refs_on_bill_ordinal"
    t.index ["bill_id"], name: "index_bill_section_references_on_bill_id"
    t.index ["key"], name: "idx_bill_section_refs_on_key"
  end

  create_table "bill_summary_prompt_snapshots", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.datetime "built_at", null: false
    t.string "summary_run_id"
    t.string "llm_model"
    t.string "llm_provider"
    t.text "bill_details_text"
    t.text "source_text"
    t.text "citations_text"
    t.text "news_text"
    t.text "facts"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_bill_summary_prompt_snapshots_on_bill_id", unique: true
  end

  create_table "bill_summary_reports", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.integer "user_id"
    t.string "reason", null: false
    t.text "details"
    t.integer "status", default: 0, null: false
    t.text "summary_snapshot"
    t.boolean "summary_ai_unreviewed", default: true, null: false
    t.string "ip_address"
    t.string "user_agent"
    t.integer "resolved_by_id"
    t.datetime "resolved_at"
    t.text "admin_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id", "created_at"], name: "index_bill_summary_reports_on_bill_id_and_created_at"
    t.index ["bill_id", "status"], name: "index_bill_summary_reports_on_bill_id_and_status"
    t.index ["bill_id"], name: "index_bill_summary_reports_on_bill_id"
    t.index ["ip_address", "created_at"], name: "index_bill_summary_reports_on_ip_address_and_created_at"
    t.index ["resolved_by_id"], name: "index_bill_summary_reports_on_resolved_by_id"
    t.index ["status"], name: "index_bill_summary_reports_on_status"
    t.index ["user_id"], name: "index_bill_summary_reports_on_user_id"
  end

  create_table "bill_summary_revisions", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.text "summary_markdown", null: false
    t.string "origin", null: false
    t.integer "actor_id"
    t.string "llm_provider"
    t.string "llm_model"
    t.string "publication_role", null: false
    t.string "review_state", null: false
    t.integer "restored_from_id"
    t.datetime "created_at", null: false
    t.integer "news_source_snapshot_id"
    t.index ["actor_id"], name: "index_bill_summary_revisions_on_actor_id"
    t.index ["bill_id", "created_at"], name: "index_bill_summary_revisions_on_bill_id_and_created_at"
    t.index ["bill_id"], name: "index_bill_summary_revisions_on_bill_id"
    t.index ["news_source_snapshot_id"], name: "index_bill_summary_revisions_on_news_source_snapshot_id"
    t.index ["restored_from_id"], name: "index_bill_summary_revisions_on_restored_from_id"
  end

  create_table "bill_views", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_bill_views_on_bill_id"
    t.index ["user_id", "bill_id"], name: "index_bill_views_on_user_id_and_bill_id", unique: true
  end

  create_table "bills", force: :cascade do |t|
    t.boolean "active"
    t.string "amendment_source"
    t.string "audio_bucket_path"
    t.string "audio_by_line"
    t.string "category", default: "", null: false
    t.string "chamber", null: false
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.string "external_version"
    t.text "extracted_text"
    t.datetime "house_vote_date_time_utc"
    t.datetime "introduced_date_time_utc", null: false
    t.datetime "last_seeded_at"
    t.integer "legislator_id", null: false
    t.string "link"
    t.datetime "parsed_at"
    t.string "parsing_target"
    t.string "parsing_target_log"
    t.date "scheduled_release_date_utc"
    t.datetime "senate_vote_date_time_utc"
    t.string "status"
    t.text "summary"
    t.integer "sway_locale_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "vote_import_state", default: "unimported", null: false
    t.integer "legislative_session_id"
    t.datetime "archived_at"
    t.index ["amendment_source"], name: "idx_bills_on_amendment_source"
    t.index ["external_id", "sway_locale_id"], name: "index_bills_on_external_id_and_sway_locale_id", unique: true
    t.index ["legislative_session_id"], name: "index_bills_on_legislative_session_id"
    t.index ["legislator_id"], name: "index_bills_on_legislator_id"
    t.index ["parsing_target"], name: "idx_bills_on_parsing_target"
    t.index ["scheduled_release_date_utc", "sway_locale_id"], name: "index_bills_on_scheduled_release_date_utc_and_sway_locale_id", unique: true
    t.index ["sway_locale_id", "archived_at"], name: "index_bills_on_sway_locale_id_and_archived_at"
    t.index ["sway_locale_id", "scheduled_release_date_utc"], name: "index_bills_on_locale_and_release_date"
    t.index ["sway_locale_id"], name: "index_bills_on_sway_locale_id"
    t.index ["vote_import_state"], name: "index_bills_on_vote_import_state"
    t.check_constraint "status IS NOT NULL AND length(trim(status, ' ' || char(9) || char(10) || char(13) || char(160) || char(8203) || char(12288))) > 0", name: "bills_status_not_blank"
  end

  create_table "campaigns", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.string "name"
    t.integer "organization_id"
    t.string "icon_url"
    t.string "support", null: false
    t.text "summary", null: false
    t.text "ai_summary"
    t.boolean "active", default: false, null: false
    t.integer "sender_count"
    t.integer "letter_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source_campaign_draft_hash"
    t.string "organization_link_decision"
    t.index ["bill_id", "name"], name: "index_campaigns_on_bill_and_name", unique: true, where: "name IS NOT NULL"
    t.index ["bill_id"], name: "index_campaigns_on_bill_id"
    t.index ["organization_id"], name: "index_campaigns_on_organization_id"
    t.index ["organization_link_decision"], name: "index_campaigns_on_organization_link_decision"
  end

  create_table "categories", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_categories_on_active"
    t.index ["name"], name: "index_categories_on_name", unique: true
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "data_migrations", primary_key: "version", id: :string, force: :cascade do |t|
  end

  create_table "districts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "sway_locale_id", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "sway_locale_id"], name: "index_districts_on_name_and_sway_locale_id", unique: true
    t.index ["sway_locale_id"], name: "index_districts_on_sway_locale_id"
  end

  create_table "historical_repair_audit_events", force: :cascade do |t|
    t.integer "historical_repair_candidate_id", null: false
    t.integer "historical_repair_preview_id"
    t.string "event_type", null: false
    t.integer "admin_user_id"
    t.string "admin_email"
    t.text "reason"
    t.json "event_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["admin_user_id"], name: "index_historical_repair_audit_events_on_admin_user_id"
    t.index ["historical_repair_candidate_id", "created_at"], name: "index_repair_audit_events_on_candidate_and_created"
    t.index ["historical_repair_candidate_id"], name: "idx_on_historical_repair_candidate_id_2960700b59"
    t.index ["historical_repair_preview_id"], name: "idx_on_historical_repair_preview_id_8722c3c615"
  end

  create_table "historical_repair_candidates", force: :cascade do |t|
    t.string "candidate_type", null: false
    t.string "target_type", null: false
    t.integer "target_id", null: false
    t.integer "legislator_id"
    t.integer "seat_id"
    t.string "seat_identifier"
    t.integer "sway_locale_id", null: false
    t.string "person_identity"
    t.json "current_values", default: {}, null: false
    t.json "proposed_values", default: {}, null: false
    t.integer "official_evidence_id"
    t.string "evidence_hash", limit: 64
    t.text "reason"
    t.string "status", default: "unapplied", null: false
    t.string "deduplication_key", null: false
    t.integer "version", default: 1, null: false
    t.string "database_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_type", "status"], name: "index_repair_candidates_on_type_and_status"
    t.index ["deduplication_key"], name: "index_repair_candidates_on_dedup_key", unique: true
    t.index ["legislator_id"], name: "index_historical_repair_candidates_on_legislator_id"
    t.index ["official_evidence_id"], name: "index_historical_repair_candidates_on_official_evidence_id"
    t.index ["seat_id"], name: "index_historical_repair_candidates_on_seat_id"
    t.index ["sway_locale_id"], name: "index_historical_repair_candidates_on_sway_locale_id"
    t.index ["target_type", "target_id"], name: "index_repair_candidates_on_target"
  end

  create_table "historical_repair_deliveries", force: :cascade do |t|
    t.integer "historical_repair_candidate_id", null: false
    t.integer "historical_repair_preview_id", null: false
    t.integer "user_id", null: false
    t.string "channel", null: false
    t.string "status", default: "pending", null: false
    t.string "suppression_reason"
    t.string "title"
    t.text "body"
    t.json "payload", default: {}, null: false
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["historical_repair_candidate_id"], name: "idx_on_historical_repair_candidate_id_77b83ca43b"
    t.index ["historical_repair_preview_id", "status"], name: "index_repair_deliveries_on_preview_and_status"
    t.index ["historical_repair_preview_id"], name: "idx_on_historical_repair_preview_id_618b09b265"
    t.index ["user_id", "channel"], name: "index_repair_deliveries_on_user_and_channel"
    t.index ["user_id"], name: "index_historical_repair_deliveries_on_user_id"
  end

  create_table "historical_repair_previews", force: :cascade do |t|
    t.integer "historical_repair_candidate_id", null: false
    t.string "preview_token", limit: 64, null: false
    t.string "calculation_status", default: "ready_for_review", null: false
    t.json "blocked_reasons", default: [], null: false
    t.json "dependency_snapshot", default: {}, null: false
    t.json "operations_payload", default: {}, null: false
    t.json "summary_counts", default: {}, null: false
    t.string "authorization_token", limit: 64
    t.string "status", default: "previewed", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["authorization_token"], name: "index_repair_previews_on_auth_token", unique: true
    t.index ["historical_repair_candidate_id"], name: "idx_on_historical_repair_candidate_id_cc170ea525"
    t.index ["preview_token"], name: "index_repair_previews_on_token", unique: true
  end

  create_table "historical_score_explanations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "historical_repair_candidate_id"
    t.integer "historical_repair_preview_id"
    t.string "score_type", null: false
    t.integer "legislator_id"
    t.float "before_score"
    t.float "after_score"
    t.float "delta"
    t.string "title", null: false
    t.text "body", null: false
    t.json "bills_summary", default: [], null: false
    t.datetime "notified_at"
    t.datetime "dismissed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["historical_repair_candidate_id"], name: "idx_on_historical_repair_candidate_id_1ccbc7ca7a"
    t.index ["historical_repair_preview_id"], name: "idx_on_historical_repair_preview_id_106ec7dd1c"
    t.index ["legislator_id"], name: "index_historical_score_explanations_on_legislator_id"
    t.index ["user_id", "created_at"], name: "index_score_explanations_on_user_and_created"
    t.index ["user_id", "dismissed_at"], name: "index_score_explanations_on_user_and_dismissed"
    t.index ["user_id"], name: "index_historical_score_explanations_on_user_id"
  end

  create_table "invites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "invitee_id", null: false
    t.integer "inviter_id", null: false
    t.datetime "updated_at", null: false
    t.index ["invitee_id"], name: "index_invites_on_invitee_id"
    t.index ["inviter_id", "invitee_id"], name: "index_invites_on_inviter_id_and_invitee_id", unique: true
  end

  create_table "law_sections", force: :cascade do |t|
    t.string "article", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "section", null: false
    t.string "source_path", null: false
    t.integer "sway_locale_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["sway_locale_id", "key"], name: "idx_law_sections_on_locale_key", unique: true
    t.index ["sway_locale_id"], name: "index_law_sections_on_sway_locale_id"
  end

  create_table "legislation_pipeline_run_bills", force: :cascade do |t|
    t.string "bill_external_id", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "legislation_pipeline_run_id", null: false
    t.integer "sort_order", default: 0, null: false
    t.json "stage_results", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_external_id"], name: "index_legislation_pipeline_run_bills_on_bill_external_id"
    t.index ["legislation_pipeline_run_id", "bill_external_id"], name: "index_prb_on_run_and_bill_external_id", unique: true
    t.index ["legislation_pipeline_run_id"], name: "idx_on_legislation_pipeline_run_id_1cc054cf9b"
  end

  create_table "legislation_pipeline_run_stages", force: :cascade do |t|
    t.text "completed_bill_external_ids", default: "[]", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "legislation_pipeline_run_id", null: false
    t.text "output_summary"
    t.text "remaining_bill_external_ids", default: "[]", null: false
    t.string "stage_name", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["legislation_pipeline_run_id", "stage_name"], name: "index_prs_on_run_and_stage_name", unique: true
    t.index ["legislation_pipeline_run_id"], name: "idx_on_legislation_pipeline_run_id_c51e3ef6b9"
  end

  create_table "legislation_pipeline_run_summary_batches", force: :cascade do |t|
    t.integer "legislation_pipeline_run_id", null: false
    t.string "batch_id", null: false
    t.datetime "submitted_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "ingested_at"
    t.integer "attempt", default: 1, null: false
    t.integer "item_count", default: 0, null: false
    t.integer "succeeded_count", default: 0, null: false
    t.integer "errored_count", default: 0, null: false
    t.integer "canceled_count", default: 0, null: false
    t.integer "expired_count", default: 0, null: false
    t.string "model"
    t.index ["batch_id"], name: "index_legislation_pipeline_run_summary_batches_on_batch_id", unique: true
    t.index ["ingested_at"], name: "index_legislation_pipeline_run_summary_batches_on_ingested_at"
    t.index ["legislation_pipeline_run_id"], name: "index_pipeline_run_summary_batches_on_run_id"
  end

  create_table "legislation_pipeline_runs", force: :cascade do |t|
    t.integer "bill_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "current_stage"
    t.boolean "download_missing_assets", default: true, null: false
    t.text "error_message"
    t.string "idempotency_key", null: false
    t.string "origin", default: "fresh", null: false
    t.string "parent_run_id"
    t.string "remote_run_id"
    t.text "stages"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.integer "sway_locale_id"
    t.index ["bill_id"], name: "index_legislation_pipeline_runs_on_bill_id"
    t.index ["idempotency_key"], name: "index_legislation_pipeline_runs_on_idempotency_key", unique: true
    t.index ["parent_run_id"], name: "index_legislation_pipeline_runs_on_parent_run_id"
    t.index ["remote_run_id"], name: "index_legislation_pipeline_runs_on_remote_run_id", unique: true, where: "remote_run_id IS NOT NULL"
    t.index ["status"], name: "index_legislation_pipeline_runs_on_status"
    t.index ["sway_locale_id"], name: "index_legislation_pipeline_runs_on_sway_locale_id"
  end

  create_table "legislative_sessions", force: :cascade do |t|
    t.integer "sway_locale_id", null: false
    t.string "name", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sway_locale_id", "active"], name: "index_legislative_sessions_on_sway_locale_id_and_active"
    t.index ["sway_locale_id", "name"], name: "index_legislative_sessions_on_sway_locale_id_and_name", unique: true
  end

  create_table "legislative_vote_coverages", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.string "chamber", null: false
    t.string "roll_call_number", null: false
    t.integer "eligible_count", default: 0, null: false
    t.integer "matched_count", default: 0, null: false
    t.json "unresolved_tokens", default: [], null: false
    t.string "status", default: "unresolved", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id", "chamber", "roll_call_number"], name: "index_vote_coverages_on_bill_chamber_and_roll", unique: true
    t.index ["bill_id"], name: "index_legislative_vote_coverages_on_bill_id"
  end

  create_table "legislator_district_scores", force: :cascade do |t|
    t.integer "count_agreed", default: 0, null: false
    t.integer "count_disagreed", default: 0, null: false
    t.integer "count_legislator_abstained", default: 0, null: false
    t.integer "count_no_legislator_vote", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "legislator_term_id", null: false
    t.datetime "updated_at", null: false
    t.integer "distinct_voter_count", default: 0, null: false
    t.index ["legislator_term_id"], name: "index_legislator_district_scores_on_legislator_term_id", unique: true
  end

  create_table "legislator_identifiers", force: :cascade do |t|
    t.integer "legislator_id", null: false
    t.integer "sway_locale_id", null: false
    t.string "source", null: false
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["legislator_id"], name: "index_legislator_identifiers_on_legislator_id"
    t.index ["sway_locale_id", "source", "value"], name: "index_legislator_identifiers_on_locale_and_source_and_value", unique: true
  end

  create_table "legislator_locale_scores", force: :cascade do |t|
    t.integer "count_agreed", default: 0, null: false
    t.integer "count_disagreed", default: 0, null: false
    t.integer "count_legislator_abstained", default: 0, null: false
    t.integer "count_no_legislator_vote", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "legislator_term_id", null: false
    t.datetime "updated_at", null: false
    t.integer "distinct_voter_count", default: 0, null: false
    t.index ["legislator_term_id"], name: "index_legislator_locale_scores_on_legislator_term_id", unique: true
  end

  create_table "legislator_terms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "district_id", null: false
    t.integer "legislator_id", null: false
    t.integer "term_end_year", null: false
    t.integer "term_start_year", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.date "ended_on"
    t.string "ended_on_source"
    t.date "began_on"
    t.string "began_on_source"
    t.integer "seat_id"
    t.index ["district_id"], name: "index_legislator_terms_on_district_id"
    t.index ["legislator_id", "term_start_year"], name: "index_legislator_terms_on_legislator_id_and_term_start_year", unique: true
    t.index ["seat_id"], name: "index_legislator_terms_on_seat_id"
  end

  create_table "legislator_update_outcomes", force: :cascade do |t|
    t.string "run_identifier", null: false
    t.integer "sway_locale_id", null: false
    t.string "person_identity", null: false
    t.integer "legislator_id"
    t.integer "seat_id"
    t.string "seat_identifier"
    t.integer "official_evidence_id"
    t.string "operation_key", null: false
    t.string "outcome", null: false
    t.text "reason"
    t.json "previous_values", default: {}, null: false
    t.json "proposed_values", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["legislator_id"], name: "index_legislator_update_outcomes_on_legislator_id"
    t.index ["official_evidence_id"], name: "index_legislator_update_outcomes_on_official_evidence_id"
    t.index ["outcome"], name: "index_legislator_update_outcomes_on_outcome"
    t.index ["run_identifier", "operation_key"], name: "index_legislator_update_outcomes_on_run_and_operation", unique: true
    t.index ["seat_id", "outcome"], name: "index_legislator_update_outcomes_on_seat_and_outcome"
    t.index ["seat_id"], name: "index_legislator_update_outcomes_on_seat_id"
    t.index ["sway_locale_id", "created_at"], name: "index_legislator_update_outcomes_on_locale_and_created_at"
    t.index ["sway_locale_id", "outcome"], name: "index_legislator_update_outcomes_on_locale_and_outcome"
    t.index ["sway_locale_id"], name: "index_legislator_update_outcomes_on_sway_locale_id"
  end

  create_table "legislator_votes", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.boolean "inferred", default: false, null: false
    t.integer "legislator_id", null: false
    t.string "source", null: false
    t.string "support", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id", "legislator_id"], name: "index_legislator_votes_on_bill_id_and_legislator_id", unique: true
    t.index ["bill_id"], name: "index_legislator_votes_on_bill_id"
    t.index ["legislator_id"], name: "index_legislator_votes_on_legislator_id"
  end

  create_table "legislators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "external_id", null: false
    t.string "fax"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.datetime "last_seeded_at"
    t.string "link"
    t.string "party", null: false
    t.string "phone"
    t.string "photo_url"
    t.integer "sway_locale_id", null: false
    t.string "twitter"
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_legislators_on_external_id"
    t.index ["sway_locale_id", "external_id"], name: "index_legislators_on_sway_locale_id_and_external_id", unique: true
    t.index ["sway_locale_id"], name: "index_legislators_on_sway_locale_id"
  end

  create_table "llm_bill_summarization_instructions", force: :cascade do |t|
    t.integer "sway_locale_id", null: false
    t.text "legislative_body_makeup"
    t.json "news_media_website_urls", default: [], null: false
    t.datetime "last_seeded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "worked_example"
    t.index ["sway_locale_id"], name: "index_llm_bill_summarization_instructions_on_sway_locale_id", unique: true
  end

  create_table "news_article_discovery_requests", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.integer "requested_by_id", null: false
    t.string "status", default: "queued", null: false
    t.string "source_config_digest", null: false
    t.string "provider", null: false
    t.string "model", null: false
    t.text "query"
    t.json "match_counts", default: {}, null: false
    t.json "diagnostics", default: [], null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id", "created_at"], name: "idx_on_bill_id_created_at_5965be0083"
    t.index ["bill_id", "status"], name: "index_news_article_discovery_requests_on_bill_id_and_status"
    t.index ["bill_id"], name: "index_news_article_discovery_requests_on_bill_id"
    t.index ["requested_by_id"], name: "index_news_article_discovery_requests_on_requested_by_id"
    t.index ["status"], name: "index_news_article_discovery_requests_on_status"
  end

  create_table "news_article_source_snapshots", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.string "purpose", null: false
    t.string "run_receipt"
    t.integer "actor_id"
    t.json "source_entries", default: [], null: false
    t.string "digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_news_article_source_snapshots_on_actor_id"
    t.index ["bill_id", "created_at"], name: "index_news_article_source_snapshots_on_bill_id_and_created_at"
    t.index ["bill_id", "purpose"], name: "index_news_article_source_snapshots_on_bill_id_and_purpose"
    t.index ["bill_id"], name: "index_news_article_source_snapshots_on_bill_id"
    t.index ["digest"], name: "index_news_article_source_snapshots_on_digest"
    t.index ["run_receipt"], name: "index_news_article_source_snapshots_on_run_receipt"
  end

  create_table "news_article_source_uses", force: :cascade do |t|
    t.integer "news_article_source_snapshot_id", null: false
    t.integer "bill_news_article_id", null: false
    t.integer "text_version_id", null: false
    t.text "claim_text", null: false
    t.text "evidence_excerpt", null: false
    t.string "citation_url", null: false
    t.string "grounding_status", default: "pending", null: false
    t.text "grounding_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_news_article_id"], name: "index_news_article_source_uses_on_bill_news_article_id"
    t.index ["bill_news_article_id"], name: "index_source_uses_on_bill_news_article_id"
    t.index ["news_article_source_snapshot_id", "grounding_status"], name: "index_source_uses_on_snapshot_and_status"
    t.index ["news_article_source_snapshot_id"], name: "idx_on_news_article_source_snapshot_id_400dbd1ea3"
    t.index ["news_article_source_snapshot_id"], name: "index_source_uses_on_snapshot_id"
    t.index ["text_version_id"], name: "index_news_article_source_uses_on_text_version_id"
    t.index ["text_version_id"], name: "index_source_uses_on_text_version_id"
  end

  create_table "news_article_testimonies", force: :cascade do |t|
    t.integer "bill_news_article_id", null: false
    t.integer "news_article_source_snapshot_id"
    t.integer "news_article_text_version_id", null: false
    t.text "argument_markdown", null: false
    t.text "evidence_excerpt", null: false
    t.string "citation_url", null: false
    t.string "author_name"
    t.string "outlet_name", null: false
    t.string "stance", null: false
    t.integer "stance_version", default: 0, null: false
    t.integer "review_version", default: 0, null: false
    t.string "text_digest", null: false
    t.string "publication_state", default: "draft", null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_news_article_id", "publication_state"], name: "idx_news_testimonies_on_bna_and_pub_state"
    t.index ["bill_news_article_id"], name: "index_news_article_testimonies_on_bill_news_article_id"
    t.index ["news_article_source_snapshot_id"], name: "idx_news_testimonies_on_snapshot_id"
    t.index ["news_article_text_version_id"], name: "idx_news_testimonies_on_text_version_id"
  end

  create_table "news_article_text_versions", force: :cascade do |t|
    t.integer "news_article_id", null: false
    t.text "text"
    t.string "digest", null: false
    t.string "origin", default: "retrieved", null: false
    t.string "extraction_status", default: "extracted", null: false
    t.integer "actor_id"
    t.string "requested_url"
    t.string "final_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_news_article_text_versions_on_actor_id"
    t.index ["digest"], name: "index_news_article_text_versions_on_digest"
    t.index ["news_article_id", "created_at"], name: "idx_on_news_article_id_created_at_fd5f7ee9a7"
    t.index ["news_article_id", "digest"], name: "index_news_article_text_versions_on_news_article_id_and_digest"
    t.index ["news_article_id"], name: "index_news_article_text_versions_on_news_article_id"
  end

  create_table "news_articles", force: :cascade do |t|
    t.string "canonical_url", null: false
    t.string "title", null: false
    t.string "outlet_name", null: false
    t.string "author_name"
    t.datetime "published_at"
    t.string "article_kind", default: "unknown", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_url"], name: "index_news_articles_on_canonical_url", unique: true
    t.index ["outlet_name"], name: "index_news_articles_on_outlet_name"
    t.index ["published_at"], name: "index_news_articles_on_published_at"
  end

  create_table "notification_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "key"], name: "index_notification_preferences_on_user_id_and_key", unique: true
  end

  create_table "official_evidence", force: :cascade do |t|
    t.string "publisher", null: false
    t.string "jurisdiction", null: false
    t.integer "sway_locale_id"
    t.text "source_url", null: false
    t.string "external_record_id"
    t.datetime "retrieved_at", null: false
    t.text "payload", null: false
    t.string "payload_hash", limit: 64, null: false
    t.string "fact_type", null: false
    t.string "fact_presence", default: "present", null: false
    t.json "parsed_values", default: {}, null: false
    t.string "date_precision"
    t.json "date_semantics", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_record_id", "jurisdiction"], name: "index_official_evidence_on_record_and_jurisdiction"
    t.index ["jurisdiction", "retrieved_at"], name: "index_official_evidence_on_jurisdiction_and_retrieved"
    t.index ["payload_hash", "source_url"], name: "index_official_evidence_on_hash_and_source", unique: true
    t.index ["sway_locale_id"], name: "index_official_evidence_on_sway_locale_id"
  end

  create_table "organization_bill_position_changes", force: :cascade do |t|
    t.integer "approved_by_id"
    t.datetime "created_at", null: false
    t.text "new_summary", null: false
    t.string "new_support", null: false
    t.integer "organization_bill_position_id", null: false
    t.text "previous_summary", null: false
    t.string "previous_support", null: false
    t.datetime "rejected_at"
    t.integer "rejected_by_id"
    t.integer "status", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_by_id", null: false
    t.index ["approved_by_id"], name: "index_organization_bill_position_changes_on_approved_by_id"
    t.index ["organization_bill_position_id"], name: "idx_on_organization_bill_position_id_789f74d3d4"
    t.index ["rejected_by_id"], name: "index_organization_bill_position_changes_on_rejected_by_id"
    t.index ["updated_by_id"], name: "index_organization_bill_position_changes_on_updated_by_id"
  end

  create_table "organization_bill_positions", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.integer "organization_id", null: false
    t.text "summary", null: false
    t.string "support", null: false
    t.datetime "updated_at", null: false
    t.text "ai_summary"
    t.datetime "activated_at"
    t.string "origin_type"
    t.integer "origin_id"
    t.string "source_kind"
    t.string "source_url"
    t.index ["active"], name: "index_organization_bill_positions_on_active"
    t.index ["bill_id", "organization_id"], name: "idx_on_bill_id_organization_id_f380340a40", unique: true
    t.index ["bill_id"], name: "index_organization_bill_positions_on_bill_id"
    t.index ["organization_id"], name: "index_organization_bill_positions_on_organization_id"
    t.index ["origin_type", "origin_id"], name: "index_organization_bill_positions_on_origin"
  end

  create_table "organization_follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "notification_cadence", default: 0, null: false
    t.boolean "notify_on_new_position", default: true, null: false
    t.boolean "notify_on_summary_change", default: true, null: false
    t.boolean "notify_on_support_change", default: true, null: false
    t.integer "organization_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["organization_id"], name: "index_organization_follows_on_organization_id"
    t.index ["user_id", "organization_id"], name: "idx_organization_follows_on_user_and_organization", unique: true
  end

  create_table "organization_notification_deliveries", force: :cascade do |t|
    t.string "change_type", null: false
    t.datetime "created_at", null: false
    t.string "delivery_token", null: false
    t.integer "organization_bill_position_id", null: false
    t.integer "user_id", null: false
    t.index ["organization_bill_position_id", "user_id", "change_type", "delivery_token"], name: "idx_org_notif_deliveries_unique", unique: true
    t.index ["user_id"], name: "index_organization_notification_deliveries_on_user_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "icon_url"
    t.string "name", null: false
    t.integer "sway_locale_id", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "sway_locale_id"], name: "index_organizations_on_name_and_sway_locale_id", unique: true
    t.index ["sway_locale_id"], name: "index_organizations_on_sway_locale_id"
  end

  create_table "passkeys", force: :cascade do |t|
    t.string "aaguid"
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "label", null: false
    t.datetime "last_used_at"
    t.string "public_key"
    t.integer "sign_count"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["external_id"], name: "index_passkeys_on_external_id", unique: true
    t.index ["public_key"], name: "index_passkeys_on_public_key", unique: true
    t.index ["user_id", "label"], name: "index_passkeys_on_user_id_and_label", unique: true
    t.index ["user_id"], name: "index_passkeys_on_user_id"
  end

  create_table "pdf_extraction_measurements", force: :cascade do |t|
    t.string "extractor", null: false
    t.string "pdf_path", null: false
    t.string "outcome", null: false
    t.string "mode"
    t.integer "wall_ms", null: false
    t.integer "service_wait_ms"
    t.integer "service_duration_ms"
    t.integer "native_ms"
    t.integer "render_ms"
    t.integer "ocr_ms"
    t.integer "page_count"
    t.integer "ocr_page_count"
    t.integer "cpu_ms"
    t.integer "peak_rss_kb"
    t.integer "text_chars"
    t.boolean "truncated", default: false, null: false
    t.string "error", limit: 300
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_pdf_extraction_measurements_on_created_at"
    t.index ["extractor", "created_at"], name: "index_pdf_extraction_measurements_on_extractor_and_created_at"
  end

  create_table "pending_organization_digest_entries", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.string "cadence", null: false
    t.string "change_types", null: false
    t.datetime "created_at", null: false
    t.integer "org_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["cadence", "created_at"], name: "idx_pending_org_digest_on_cadence_created_at"
    t.index ["user_id"], name: "index_pending_organization_digest_entries_on_user_id"
  end

  create_table "pipeline_activity_log_entries", force: :cascade do |t|
    t.integer "actor_user_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "message", null: false
    t.text "payload", default: "{}", null: false
    t.string "severity", null: false
    t.string "subject_id"
    t.string "subject_type"
    t.string "title", null: false
    t.index ["actor_user_id"], name: "index_pipeline_activity_log_entries_on_actor_user_id"
    t.index ["created_at"], name: "index_activity_log_entries_on_created_at_desc", order: :desc
    t.index ["event_type"], name: "index_pipeline_activity_log_entries_on_event_type"
    t.index ["severity", "created_at"], name: "index_activity_log_severity_and_created_at", order: { created_at: :desc }
    t.index ["subject_type", "subject_id"], name: "index_activity_log_entries_on_subject_polymorphic"
  end

  create_table "push_notification_subscriptions", force: :cascade do |t|
    t.string "auth"
    t.datetime "created_at", null: false
    t.string "endpoint"
    t.string "p256dh"
    t.boolean "subscribed", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "endpoint"], name: "index_push_notification_subscriptions_on_user_id_and_endpoint", unique: true
  end

  create_table "refresh_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "ip_address", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent", null: false
    t.integer "user_id", null: false
    t.index ["token"], name: "index_refresh_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_refresh_tokens_on_user_id"
  end

  create_table "registration_funnel_events", force: :cascade do |t|
    t.string "visitor_token", limit: 64, null: false
    t.integer "user_id"
    t.integer "step", null: false
    t.string "attribution_key", limit: 100
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "bot", default: false, null: false
    t.index ["attribution_key", "created_at"], name: "index_registration_funnel_events_on_attribution_and_created_at"
    t.index ["bot", "step", "created_at"], name: "index_registration_funnel_events_on_bot_step_created_at"
    t.index ["step", "created_at"], name: "index_registration_funnel_events_on_step_and_created_at"
    t.index ["user_id"], name: "index_registration_funnel_events_on_user_id"
    t.index ["visitor_token"], name: "index_registration_funnel_events_on_visitor_token"
  end

  create_table "replication_heartbeats", force: :cascade do |t|
    t.datetime "checked_at", null: false
    t.integer "last_replica_txid"
    t.integer "consecutive_stalls", default: 0, null: false
    t.integer "consecutive_read_failures", default: 0, null: false
    t.integer "consecutive_empty_listings", default: 0, null: false
    t.datetime "stalled_since"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "id = 1", name: "replication_heartbeats_single_row"
  end

  create_table "representative_reassignments", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "district_id"
    t.integer "previous_district_id"
    t.integer "legislator_id"
    t.integer "previous_legislator_id"
    t.integer "reassignment_type", default: 0, null: false
    t.datetime "notified_at"
    t.datetime "dismissed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["district_id"], name: "index_representative_reassignments_on_district_id"
    t.index ["legislator_id"], name: "index_representative_reassignments_on_legislator_id"
    t.index ["previous_district_id"], name: "index_representative_reassignments_on_previous_district_id"
    t.index ["previous_legislator_id"], name: "index_representative_reassignments_on_previous_legislator_id"
    t.index ["user_id", "dismissed_at"], name: "idx_rep_reassign_user_active"
    t.index ["user_id", "district_id", "legislator_id", "previous_legislator_id"], name: "idx_rep_reassign_full_unique", unique: true, where: "previous_legislator_id IS NOT NULL AND legislator_id IS NOT NULL"
    t.index ["user_id", "district_id", "legislator_id"], name: "idx_rep_reassign_filled_unique", unique: true, where: "previous_legislator_id IS NULL"
    t.index ["user_id", "district_id", "previous_legislator_id"], name: "idx_rep_reassign_vacant_unique", unique: true, where: "legislator_id IS NULL"
    t.index ["user_id"], name: "index_representative_reassignments_on_user_id"
  end

  create_table "roll_calls", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.integer "house_roll_call_vote_number"
    t.integer "senate_roll_call_vote_number"
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_roll_calls_on_bill_id"
  end

  create_table "seats", force: :cascade do |t|
    t.integer "district_id", null: false
    t.string "seat_identifier", null: false
    t.string "title", null: false
    t.string "chamber", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["district_id", "seat_identifier"], name: "index_seats_on_district_id_and_seat_identifier", unique: true
    t.index ["district_id"], name: "index_seats_on_district_id"
  end

  create_table "sending_service_domain_bills", force: :cascade do |t|
    t.integer "sending_service_domain_id", null: false
    t.integer "bill_id", null: false
    t.integer "sender_count", null: false
    t.integer "letter_count", null: false
    t.integer "machine_sent_letter_count", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_sending_service_domain_bills_on_bill_id"
    t.index ["sending_service_domain_id", "bill_id"], name: "index_sending_service_domain_bills_on_domain_and_bill", unique: true
  end

  create_table "sending_service_domains", force: :cascade do |t|
    t.string "domain", null: false
    t.string "label", default: "none", null: false
    t.integer "confirmed_by_id"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["confirmed_by_id"], name: "index_sending_service_domains_on_confirmed_by_id"
    t.index ["domain"], name: "index_sending_service_domains_on_domain", unique: true
  end

  create_table "shortened_urls", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", precision: nil
    t.datetime "expires_at", precision: nil
    t.integer "owner_id"
    t.string "owner_type", limit: 20
    t.string "unique_key", limit: 10, null: false
    t.datetime "updated_at", precision: nil
    t.text "url", null: false
    t.integer "use_count", default: 0, null: false
    t.index ["category"], name: "index_shortened_urls_on_category"
    t.index ["owner_id", "owner_type"], name: "index_shortened_urls_on_owner_id_and_owner_type"
    t.index ["unique_key"], name: "index_shortened_urls_on_unique_key", unique: true
    t.index ["url"], name: "index_shortened_urls_on_url"
  end

  create_table "sway_locales", force: :cascade do |t|
    t.string "city", null: false
    t.string "country", default: "United States", null: false
    t.datetime "created_at", null: false
    t.string "icon_url"
    t.datetime "last_seeded_at"
    t.integer "latest_election_year", default: 2024, null: false
    t.datetime "legislators_cache_fetched_at"
    t.string "region_name", null: false
    t.string "time_zone"
    t.datetime "updated_at", null: false
    t.string "sample_street"
    t.string "sample_postal_code"
    t.float "sample_latitude"
    t.float "sample_longitude"
    t.index ["city", "region_name", "country"], name: "index_sway_locales_on_city_and_region_name_and_country", unique: true
  end

  create_table "testimony_attachment_classifications", force: :cascade do |t|
    t.string "source_endpoint", null: false
    t.integer "attachment_id", null: false
    t.string "label", null: false
    t.string "model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "prompt_version"
    t.integer "sway_locale_id", null: false
    t.index ["sway_locale_id", "attachment_id"], name: "index_testimony_classifications_on_locale_and_attachment", unique: true
  end

  create_table "testimony_coverage_acknowledgements", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.integer "acknowledged_by_id", null: false
    t.string "coverage_digest", null: false
    t.integer "legislation_pipeline_run_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["acknowledged_by_id"], name: "idx_on_acknowledged_by_id_9c5b8c3023"
    t.index ["bill_id", "coverage_digest"], name: "index_testimony_coverage_acks_on_bill_and_digest", unique: true
    t.index ["bill_id"], name: "index_testimony_coverage_acknowledgements_on_bill_id"
    t.index ["legislation_pipeline_run_id"], name: "idx_on_legislation_pipeline_run_id_e73c32c2d5"
  end

  create_table "user_address_changes", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "previous_address_id", null: false
    t.integer "new_address_id", null: false
    t.json "deactivated_legislator_ids", default: [], null: false
    t.json "activated_legislator_ids", default: [], null: false
    t.json "deactivated_district_ids", default: [], null: false
    t.json "activated_district_ids", default: [], null: false
    t.json "previous_sway_locale_ids", default: [], null: false
    t.json "new_sway_locale_ids", default: [], null: false
    t.integer "prior_vote_count", default: 0, null: false
    t.json "prior_voted_bill_ids", default: [], null: false
    t.json "prior_voted_sway_locale_ids", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_user_address_changes_on_created_at"
    t.index ["new_address_id"], name: "index_user_address_changes_on_new_address_id"
    t.index ["previous_address_id"], name: "index_user_address_changes_on_previous_address_id"
    t.index ["user_id", "created_at"], name: "index_user_address_changes_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_user_address_changes_on_user_id"
  end

  create_table "user_addresses", force: :cascade do |t|
    t.integer "address_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["address_id"], name: "index_user_addresses_on_address_id"
    t.index ["user_id"], name: "index_user_addresses_on_user_id", unique: true
  end

  create_table "user_bill_reminders", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.datetime "sent_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["bill_id"], name: "index_user_bill_reminders_on_bill_id"
    t.index ["user_id"], name: "index_user_bill_reminders_on_user_id"
  end

  create_table "user_bill_shares", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "bill_id", null: false
    t.string "share_uuid", null: false
    t.datetime "redeemed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_user_bill_shares_on_bill_id"
    t.index ["share_uuid"], name: "index_user_bill_shares_on_share_uuid", unique: true
    t.index ["user_id", "bill_id"], name: "index_user_bill_shares_on_user_id_and_bill_id", unique: true
  end

  create_table "user_devices", force: :cascade do |t|
    t.string "app_version"
    t.datetime "created_at", null: false
    t.datetime "last_seen_at", null: false
    t.string "platform", null: false
    t.string "push_token"
    t.datetime "revoked_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["push_token"], name: "index_user_devices_on_push_token"
    t.index ["push_token"], name: "index_user_devices_on_push_token_active", unique: true, where: "revoked_at IS NULL"
    t.index ["user_id", "revoked_at"], name: "index_user_devices_on_user_id_and_revoked_at"
    t.index ["user_id"], name: "index_user_devices_on_user_id"
  end

  create_table "user_districts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "district_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "district_id"], name: "index_user_districts_on_user_id_and_district_id", unique: true
  end

  create_table "user_invite_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "invite_uuid", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["invite_uuid"], name: "index_user_invite_links_on_invite_uuid", unique: true
    t.index ["user_id"], name: "index_user_invite_links_on_user_id"
  end

  create_table "user_legislator_emails", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.integer "status", null: false
    t.datetime "updated_at", null: false
    t.integer "user_legislator_id", null: false
    t.index ["bill_id"], name: "index_user_legislator_emails_on_bill_id"
    t.index ["user_legislator_id", "bill_id"], name: "index_user_legislator_emails_on_ul_and_bill", unique: true
    t.index ["user_legislator_id"], name: "index_user_legislator_emails_on_user_legislator_id"
  end

  create_table "user_legislator_term_scores", force: :cascade do |t|
    t.integer "count_agreed", default: 0, null: false
    t.integer "count_disagreed", default: 0, null: false
    t.integer "count_legislator_abstained", default: 0, null: false
    t.integer "count_no_legislator_vote", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "legislator_term_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_legislator_id", null: false
    t.index ["user_legislator_id", "legislator_term_id"], name: "index_user_legislator_term_scores_on_ul_and_term", unique: true
  end

  create_table "user_legislators", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "legislator_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["legislator_id"], name: "index_user_legislators_on_legislator_id"
    t.index ["user_id", "legislator_id"], name: "by_unique_user_and_legislator", unique: true
  end

  create_table "user_organization_membership_invites", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "invitee_email", null: false
    t.integer "invitee_user_id"
    t.integer "inviter_id", null: false
    t.integer "organization_id", null: false
    t.datetime "revoked_at"
    t.datetime "updated_at", null: false
    t.index ["accepted_at"], name: "index_user_organization_membership_invites_on_accepted_at"
    t.index ["expires_at"], name: "index_user_organization_membership_invites_on_expires_at"
    t.index ["invitee_user_id"], name: "index_user_organization_membership_invites_on_invitee_user_id"
    t.index ["inviter_id"], name: "index_user_organization_membership_invites_on_inviter_id"
    t.index ["organization_id"], name: "index_user_organization_membership_invites_on_organization_id"
    t.index ["revoked_at"], name: "index_user_organization_membership_invites_on_revoked_at"
  end

  create_table "user_organization_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "organization_id", null: false
    t.integer "role", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["organization_id"], name: "index_user_organization_memberships_on_organization_id"
    t.index ["user_id", "organization_id"], name: "idx_on_user_id_organization_id_7cc0c85071", unique: true
    t.index ["user_id"], name: "index_user_organization_memberships_on_user_id"
  end

  create_table "user_votes", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.string "support", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["bill_id"], name: "index_user_votes_on_bill_id"
    t.index ["user_id", "bill_id"], name: "index_user_votes_on_user_id_and_bill_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email"
    t.string "full_name"
    t.boolean "is_email_verified"
    t.boolean "is_phone_verified"
    t.boolean "is_registered_to_vote"
    t.boolean "is_registration_complete"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.boolean "notify_on_new_position_default", default: true, null: false
    t.boolean "notify_on_summary_change_default", default: true, null: false
    t.boolean "notify_on_support_change_default", default: true, null: false
    t.integer "org_position_cadence_default", default: 0, null: false
    t.string "phone"
    t.string "registration_status", default: "pending"
    t.integer "sign_in_count", default: 0, null: false
    t.boolean "sms_notifications_enabled", default: false
    t.string "theme", default: "neutral", null: false
    t.string "theme_mode", default: "light", null: false
    t.datetime "updated_at", null: false
    t.string "webauthn_id"
    t.boolean "is_voter_registration_address_confirmed", default: false, null: false
    t.json "pending_representative_locale_ids", default: [], null: false
    t.integer "session_generation", default: 0, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["phone"], name: "index_users_on_phone", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  add_foreign_key "admin_bill_views", "bills"
  add_foreign_key "admin_bill_views", "users", column: "admin_user_id"
  add_foreign_key "admin_settings", "users", column: "updated_by_id"
  add_foreign_key "api_keys", "user_devices"
  add_foreign_key "article_bills", "bills"
  add_foreign_key "article_bills", "organizations"
  add_foreign_key "bill_amendment_operations", "bill_section_references"
  add_foreign_key "bill_amendment_operations", "bills"
  add_foreign_key "bill_amendment_operations", "law_sections", column: "target_law_section_id"
  add_foreign_key "bill_categories", "bills"
  add_foreign_key "bill_categories", "categories"
  add_foreign_key "bill_cosponsors", "bills"
  add_foreign_key "bill_cosponsors", "legislators"
  add_foreign_key "bill_interesting_scores", "bills"
  add_foreign_key "bill_llm_provisionings", "bills"
  add_foreign_key "bill_news_articles", "bills", on_delete: :cascade
  add_foreign_key "bill_news_articles", "news_article_text_versions", column: "current_text_version_id", on_delete: :restrict
  add_foreign_key "bill_news_articles", "news_articles", on_delete: :restrict
  add_foreign_key "bill_news_articles", "users", column: "approved_by_id"
  add_foreign_key "bill_news_articles", "users", column: "stance_by_id"
  add_foreign_key "bill_notifications", "bills"
  add_foreign_key "bill_score_districts", "bill_scores"
  add_foreign_key "bill_score_districts", "districts"
  add_foreign_key "bill_scores", "bills"
  add_foreign_key "bill_section_references", "bills"
  add_foreign_key "bill_summary_prompt_snapshots", "bills"
  add_foreign_key "bill_summary_reports", "bills", on_delete: :cascade
  add_foreign_key "bill_summary_reports", "users", column: "resolved_by_id", on_delete: :nullify
  add_foreign_key "bill_summary_reports", "users", on_delete: :nullify
  add_foreign_key "bill_summary_revisions", "bill_summary_revisions", column: "restored_from_id"
  add_foreign_key "bill_summary_revisions", "bills"
  add_foreign_key "bill_summary_revisions", "news_article_source_snapshots", column: "news_source_snapshot_id", on_delete: :nullify
  add_foreign_key "bill_summary_revisions", "users", column: "actor_id"
  add_foreign_key "bill_views", "bills"
  add_foreign_key "bill_views", "users"
  add_foreign_key "bills", "legislative_sessions", on_delete: :nullify
  add_foreign_key "bills", "legislators"
  add_foreign_key "bills", "sway_locales"
  add_foreign_key "campaigns", "bills"
  add_foreign_key "campaigns", "organizations"
  add_foreign_key "districts", "sway_locales"
  add_foreign_key "historical_repair_audit_events", "historical_repair_candidates"
  add_foreign_key "historical_repair_audit_events", "historical_repair_previews"
  add_foreign_key "historical_repair_audit_events", "users", column: "admin_user_id"
  add_foreign_key "historical_repair_candidates", "legislators"
  add_foreign_key "historical_repair_candidates", "official_evidence"
  add_foreign_key "historical_repair_candidates", "seats"
  add_foreign_key "historical_repair_candidates", "sway_locales"
  add_foreign_key "historical_repair_deliveries", "historical_repair_candidates"
  add_foreign_key "historical_repair_deliveries", "historical_repair_previews"
  add_foreign_key "historical_repair_deliveries", "users", on_delete: :cascade
  add_foreign_key "historical_repair_previews", "historical_repair_candidates"
  add_foreign_key "historical_score_explanations", "historical_repair_candidates"
  add_foreign_key "historical_score_explanations", "historical_repair_previews"
  add_foreign_key "historical_score_explanations", "legislators"
  add_foreign_key "historical_score_explanations", "users", on_delete: :cascade
  add_foreign_key "invites", "users", column: "invitee_id"
  add_foreign_key "invites", "users", column: "inviter_id"
  add_foreign_key "law_sections", "sway_locales"
  add_foreign_key "legislation_pipeline_run_bills", "legislation_pipeline_runs", on_delete: :cascade
  add_foreign_key "legislation_pipeline_run_stages", "legislation_pipeline_runs", on_delete: :cascade
  add_foreign_key "legislation_pipeline_run_summary_batches", "legislation_pipeline_runs", on_delete: :cascade
  add_foreign_key "legislation_pipeline_runs", "bills"
  add_foreign_key "legislation_pipeline_runs", "sway_locales"
  add_foreign_key "legislative_sessions", "sway_locales"
  add_foreign_key "legislative_vote_coverages", "bills"
  add_foreign_key "legislator_identifiers", "legislators"
  add_foreign_key "legislator_identifiers", "sway_locales"
  add_foreign_key "legislator_terms", "districts"
  add_foreign_key "legislator_terms", "legislators"
  add_foreign_key "legislator_terms", "seats"
  add_foreign_key "legislator_update_outcomes", "legislators"
  add_foreign_key "legislator_update_outcomes", "official_evidence"
  add_foreign_key "legislator_update_outcomes", "seats"
  add_foreign_key "legislator_update_outcomes", "sway_locales"
  add_foreign_key "legislator_votes", "bills"
  add_foreign_key "legislator_votes", "legislators"
  add_foreign_key "legislators", "sway_locales"
  add_foreign_key "llm_bill_summarization_instructions", "sway_locales"
  add_foreign_key "news_article_discovery_requests", "bills", on_delete: :cascade
  add_foreign_key "news_article_discovery_requests", "users", column: "requested_by_id", on_delete: :restrict
  add_foreign_key "news_article_source_snapshots", "bills", on_delete: :cascade
  add_foreign_key "news_article_source_snapshots", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "news_article_source_uses", "bill_news_articles", on_delete: :restrict
  add_foreign_key "news_article_source_uses", "news_article_source_snapshots", on_delete: :cascade
  add_foreign_key "news_article_source_uses", "news_article_text_versions", column: "text_version_id", on_delete: :restrict
  add_foreign_key "news_article_testimonies", "bill_news_articles", on_delete: :cascade
  add_foreign_key "news_article_testimonies", "news_article_source_snapshots", on_delete: :nullify
  add_foreign_key "news_article_testimonies", "news_article_text_versions", on_delete: :restrict
  add_foreign_key "news_article_text_versions", "news_articles", on_delete: :restrict
  add_foreign_key "news_article_text_versions", "users", column: "actor_id"
  add_foreign_key "notification_preferences", "users"
  add_foreign_key "official_evidence", "sway_locales"
  add_foreign_key "organization_bill_position_changes", "organization_bill_positions"
  add_foreign_key "organization_bill_position_changes", "users", column: "approved_by_id"
  add_foreign_key "organization_bill_position_changes", "users", column: "rejected_by_id"
  add_foreign_key "organization_bill_position_changes", "users", column: "updated_by_id"
  add_foreign_key "organization_bill_positions", "bills"
  add_foreign_key "organization_bill_positions", "organizations"
  add_foreign_key "organization_follows", "organizations"
  add_foreign_key "organization_follows", "users"
  add_foreign_key "organizations", "sway_locales"
  add_foreign_key "passkeys", "users"
  add_foreign_key "pipeline_activity_log_entries", "users", column: "actor_user_id"
  add_foreign_key "push_notification_subscriptions", "users"
  add_foreign_key "refresh_tokens", "users"
  add_foreign_key "registration_funnel_events", "users", on_delete: :nullify
  add_foreign_key "representative_reassignments", "districts"
  add_foreign_key "representative_reassignments", "districts", column: "previous_district_id"
  add_foreign_key "representative_reassignments", "legislators"
  add_foreign_key "representative_reassignments", "legislators", column: "previous_legislator_id"
  add_foreign_key "representative_reassignments", "users", on_delete: :cascade
  add_foreign_key "roll_calls", "bills"
  add_foreign_key "seats", "districts"
  add_foreign_key "sending_service_domain_bills", "bills"
  add_foreign_key "sending_service_domain_bills", "sending_service_domains"
  add_foreign_key "sending_service_domains", "users", column: "confirmed_by_id"
  add_foreign_key "testimony_attachment_classifications", "sway_locales"
  add_foreign_key "testimony_coverage_acknowledgements", "bills"
  add_foreign_key "testimony_coverage_acknowledgements", "legislation_pipeline_runs"
  add_foreign_key "testimony_coverage_acknowledgements", "users", column: "acknowledged_by_id"
  add_foreign_key "user_address_changes", "users", on_delete: :cascade
  add_foreign_key "user_addresses", "addresses"
  add_foreign_key "user_addresses", "users"
  add_foreign_key "user_bill_reminders", "bills"
  add_foreign_key "user_bill_reminders", "users"
  add_foreign_key "user_bill_shares", "bills"
  add_foreign_key "user_bill_shares", "users"
  add_foreign_key "user_devices", "users"
  add_foreign_key "user_districts", "districts"
  add_foreign_key "user_districts", "users"
  add_foreign_key "user_invite_links", "users"
  add_foreign_key "user_legislator_emails", "bills"
  add_foreign_key "user_legislator_emails", "user_legislators"
  add_foreign_key "user_legislator_term_scores", "legislator_terms"
  add_foreign_key "user_legislator_term_scores", "user_legislators"
  add_foreign_key "user_legislators", "legislators"
  add_foreign_key "user_legislators", "users"
  add_foreign_key "user_organization_membership_invites", "organizations"
  add_foreign_key "user_organization_membership_invites", "users", column: "invitee_user_id"
  add_foreign_key "user_organization_membership_invites", "users", column: "inviter_id"
  add_foreign_key "user_organization_memberships", "organizations"
  add_foreign_key "user_organization_memberships", "users"
  add_foreign_key "user_votes", "bills"
  add_foreign_key "user_votes", "users"
end
