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

ActiveRecord::Schema[8.0].define(version: 2025_02_22_184210) do
  create_table "addresses", force: :cascade do |t|
    t.string "street", null: false
    t.string "street2"
    t.string "street3"
    t.string "city", null: false
    t.string "region_code", null: false
    t.string "postal_code", null: false
    t.string "country", default: "US", null: false
    t.float "latitude"
    t.float "longitude"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["latitude", "longitude"], name: "index_addresses_on_latitude_and_longitude"
  end

  create_table "api_keys", force: :cascade do |t|
    t.integer "bearer_id", null: false
    t.string "bearer_type", null: false
    t.string "token_digest", null: false
    t.string "name"
    t.datetime "last_used_on_utc"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bearer_id", "bearer_type"], name: "index_api_keys_on_bearer_id_and_bearer_type"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
  end

  create_table "bill_cosponsors", force: :cascade do |t|
    t.integer "legislator_id", null: false
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_bill_cosponsors_on_bill_id"
    t.index ["legislator_id"], name: "index_bill_cosponsors_on_legislator_id"
  end

  create_table "bill_score_districts", force: :cascade do |t|
    t.integer "bill_score_id", null: false
    t.integer "district_id", null: false
    t.integer "for", default: 0, null: false
    t.integer "against", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_score_id"], name: "index_bill_score_districts_on_bill_score_id"
    t.index ["district_id"], name: "index_bill_score_districts_on_district_id"
  end

  create_table "bill_scores", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.integer "for", default: 0, null: false
    t.integer "against", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_bill_scores_on_bill_id"
  end

  create_table "bills", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "external_version"
    t.string "title", null: false
    t.string "link"
    t.string "chamber", null: false
    t.datetime "introduced_date_time_utc", null: false
    t.datetime "house_vote_date_time_utc"
    t.datetime "senate_vote_date_time_utc"
    t.string "category", null: false
    t.text "summary"
    t.integer "legislator_id", null: false
    t.integer "sway_locale_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status"
    t.boolean "active"
    t.string "audio_bucket_path"
    t.string "audio_by_line"
    t.date "scheduled_release_date_utc"
    t.index ["external_id", "sway_locale_id"], name: "index_bills_on_external_id_and_sway_locale_id", unique: true
    t.index ["legislator_id"], name: "index_bills_on_legislator_id"
    t.index ["scheduled_release_date_utc", "sway_locale_id"], name: "index_bills_on_scheduled_release_date_utc_and_sway_locale_id", unique: true
    t.index ["sway_locale_id"], name: "index_bills_on_sway_locale_id"
  end

  create_table "districts", force: :cascade do |t|
    t.string "name", null: false
    t.integer "sway_locale_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "sway_locale_id"], name: "index_districts_on_name_and_sway_locale_id", unique: true
    t.index ["sway_locale_id"], name: "index_districts_on_sway_locale_id"
  end

  create_table "invites", force: :cascade do |t|
    t.integer "inviter_id", null: false
    t.integer "invitee_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invitee_id"], name: "index_invites_on_invitee_id"
    t.index ["inviter_id"], name: "index_invites_on_inviter_id"
    t.index ["inviter_id"], name: "index_invites_on_inviter_id_and_inviter_id", unique: true
  end

  create_table "legislator_district_scores", force: :cascade do |t|
    t.integer "legislator_id", null: false
    t.integer "count_agreed", default: 0, null: false
    t.integer "count_disagreed", default: 0, null: false
    t.integer "count_no_legislator_vote", default: 0, null: false
    t.integer "count_legislator_abstained", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["legislator_id"], name: "index_legislator_district_scores_on_legislator_id"
  end

  create_table "legislator_votes", force: :cascade do |t|
    t.integer "legislator_id", null: false
    t.integer "bill_id", null: false
    t.string "support", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_legislator_votes_on_bill_id"
    t.index ["legislator_id"], name: "index_legislator_votes_on_legislator_id"
  end

  create_table "legislators", force: :cascade do |t|
    t.string "external_id", null: false
    t.boolean "active", null: false
    t.string "link"
    t.string "email"
    t.string "title"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "phone"
    t.string "fax"
    t.string "party", null: false
    t.string "photo_url"
    t.integer "district_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "twitter"
    t.index ["district_id"], name: "index_legislators_on_district_id"
  end

  create_table "organization_bill_positions", force: :cascade do |t|
    t.integer "bill_id", null: false
    t.integer "organization_id", null: false
    t.string "support", null: false
    t.text "summary", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id", "organization_id"], name: "idx_on_bill_id_organization_id_f380340a40", unique: true
    t.index ["bill_id"], name: "index_organization_bill_positions_on_bill_id"
    t.index ["organization_id"], name: "index_organization_bill_positions_on_organization_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.integer "sway_locale_id", null: false
    t.string "name", null: false
    t.string "icon_path"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "sway_locale_id"], name: "index_organizations_on_name_and_sway_locale_id", unique: true
    t.index ["sway_locale_id"], name: "index_organizations_on_sway_locale_id"
  end

  create_table "passkeys", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "label", null: false
    t.string "external_id"
    t.string "public_key"
    t.integer "sign_count"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_passkeys_on_external_id", unique: true
    t.index ["public_key"], name: "index_passkeys_on_public_key", unique: true
    t.index ["user_id"], name: "index_passkeys_on_user_id"
  end

  create_table "push_notification_subscriptions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "endpoint"
    t.string "p256dh"
    t.string "auth"
    t.boolean "subscribed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_push_notification_subscriptions_on_user_id"
  end

  create_table "refresh_tokens", force: :cascade do |t|
    t.integer "user_id", null: false
    t.datetime "expires_at", null: false
    t.string "token", null: false
    t.string "ip_address", null: false
    t.string "user_agent", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_refresh_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_refresh_tokens_on_user_id"
  end

  create_table "shortened_urls", force: :cascade do |t|
    t.integer "owner_id"
    t.string "owner_type", limit: 20
    t.text "url", null: false
    t.string "unique_key", limit: 10, null: false
    t.string "category"
    t.integer "use_count", default: 0, null: false
    t.datetime "expires_at", precision: nil
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["category"], name: "index_shortened_urls_on_category"
    t.index ["owner_id", "owner_type"], name: "index_shortened_urls_on_owner_id_and_owner_type"
    t.index ["unique_key"], name: "index_shortened_urls_on_unique_key", unique: true
    t.index ["url"], name: "index_shortened_urls_on_url"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "sway_locales", force: :cascade do |t|
    t.string "city", null: false
    t.string "state", null: false
    t.string "country", default: "United States", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "current_session_start_date"
    t.string "time_zone"
    t.string "icon_path"
    t.integer "latest_election_year", default: 2024, null: false
    t.index ["city", "state", "country"], name: "index_sway_locales_on_city_and_state_and_country", unique: true
  end

  create_table "user_addresses", force: :cascade do |t|
    t.integer "address_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["address_id"], name: "index_user_addresses_on_address_id"
    t.index ["user_id"], name: "index_user_addresses_on_user_id"
  end

  create_table "user_districts", force: :cascade do |t|
    t.integer "district_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["district_id"], name: "index_user_districts_on_district_id"
    t.index ["user_id"], name: "index_user_districts_on_user_id"
  end

  create_table "user_inviters", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "invite_uuid", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invite_uuid"], name: "index_user_inviters_on_invite_uuid", unique: true
    t.index ["user_id"], name: "index_user_inviters_on_user_id"
  end

  create_table "user_legislator_emails", force: :cascade do |t|
    t.integer "user_legislator_id", null: false
    t.integer "user_vote_id", null: false
    t.string "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "bill_id"
    t.integer "status", null: false
    t.index ["bill_id"], name: "index_user_legislator_emails_on_bill_id"
    t.index ["user_legislator_id"], name: "index_user_legislator_emails_on_user_legislator_id"
    t.index ["user_vote_id"], name: "index_user_legislator_emails_on_user_vote_id"
  end

  create_table "user_legislator_scores", force: :cascade do |t|
    t.integer "user_legislator_id", null: false
    t.integer "count_agreed", default: 0, null: false
    t.integer "count_disagreed", default: 0, null: false
    t.integer "count_no_legislator_vote", default: 0, null: false
    t.integer "count_legislator_abstained", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_legislator_id"], name: "index_user_legislator_scores_on_user_legislator_id"
  end

  create_table "user_legislators", force: :cascade do |t|
    t.integer "legislator_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true, null: false
    t.index ["legislator_id"], name: "index_user_legislators_on_legislator_id"
    t.index ["user_id"], name: "index_user_legislators_on_user_id"
  end

  create_table "user_votes", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "bill_id", null: false
    t.string "support", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_user_votes_on_bill_id"
    t.index ["user_id"], name: "index_user_votes_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.boolean "is_email_verified"
    t.string "phone"
    t.boolean "is_phone_verified"
    t.boolean "is_registration_complete"
    t.boolean "is_registered_to_vote"
    t.boolean "is_admin", default: false
    t.string "webauthn_id"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "full_name"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["phone"], name: "index_users_on_phone", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  create_table "votes", force: :cascade do |t|
    t.integer "house_roll_call_vote_number"
    t.integer "senate_roll_call_vote_number"
    t.integer "bill_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_votes_on_bill_id"
  end

  add_foreign_key "bill_cosponsors", "bills"
  add_foreign_key "bill_cosponsors", "legislators"
  add_foreign_key "bill_score_districts", "bill_scores"
  add_foreign_key "bill_score_districts", "districts"
  add_foreign_key "bill_scores", "bills"
  add_foreign_key "bills", "legislators"
  add_foreign_key "bills", "sway_locales"
  add_foreign_key "districts", "sway_locales"
  add_foreign_key "invites", "users", column: "invitee_id"
  add_foreign_key "invites", "users", column: "inviter_id"
  add_foreign_key "legislator_district_scores", "legislators"
  add_foreign_key "legislator_votes", "bills"
  add_foreign_key "legislator_votes", "legislators"
  add_foreign_key "legislators", "districts"
  add_foreign_key "organization_bill_positions", "bills"
  add_foreign_key "organization_bill_positions", "organizations"
  add_foreign_key "organizations", "sway_locales"
  add_foreign_key "passkeys", "users"
  add_foreign_key "push_notification_subscriptions", "users"
  add_foreign_key "refresh_tokens", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "user_addresses", "addresses"
  add_foreign_key "user_addresses", "users"
  add_foreign_key "user_districts", "districts"
  add_foreign_key "user_districts", "users"
  add_foreign_key "user_inviters", "users"
  add_foreign_key "user_legislator_emails", "bills"
  add_foreign_key "user_legislator_emails", "user_legislators"
  add_foreign_key "user_legislator_emails", "user_votes"
  add_foreign_key "user_legislator_scores", "user_legislators"
  add_foreign_key "user_legislators", "legislators"
  add_foreign_key "user_legislators", "users"
  add_foreign_key "user_votes", "bills"
  add_foreign_key "user_votes", "users"
  add_foreign_key "votes", "bills"
end
