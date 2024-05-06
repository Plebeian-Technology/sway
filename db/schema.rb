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

ActiveRecord::Schema[7.1].define(version: 2024_05_05_205329) do
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
    t.string "level", null: false
    t.string "category", null: false
    t.text "summary"
    t.integer "legislator_id", null: false
    t.integer "sway_locale_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["legislator_id"], name: "index_bills_on_legislator_id"
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

  create_table "legislator_district_scores", force: :cascade do |t|
    t.integer "district_id", null: false
    t.integer "legislator_id", null: false
    t.integer "count_agreed", default: 0, null: false
    t.integer "count_disagreed", default: 0, null: false
    t.integer "count_no_legislator_vote", default: 0, null: false
    t.integer "count_legislator_abstained", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["district_id"], name: "index_legislator_district_scores_on_district_id"
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
    t.integer "address_id", null: false
    t.integer "district_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "twitter"
    t.index ["address_id"], name: "index_legislators_on_address_id"
    t.index ["district_id"], name: "index_legislators_on_district_id"
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

  create_table "sway_locales", force: :cascade do |t|
    t.string "city", null: false
    t.string "state", null: false
    t.string "country", default: "United States", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "user_invites", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "invitee_email"
    t.datetime "invite_expires_on_utc"
    t.datetime "invite_accepted_on_utc"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_invites_on_user_id"
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["phone"], name: "index_users_on_phone", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  add_foreign_key "bill_cosponsors", "bills"
  add_foreign_key "bill_cosponsors", "legislators"
  add_foreign_key "bill_score_districts", "bill_scores"
  add_foreign_key "bill_score_districts", "districts"
  add_foreign_key "bill_scores", "bills"
  add_foreign_key "bills", "legislators"
  add_foreign_key "bills", "sway_locales"
  add_foreign_key "districts", "sway_locales"
  add_foreign_key "legislator_district_scores", "districts"
  add_foreign_key "legislator_district_scores", "legislators"
  add_foreign_key "legislator_votes", "bills"
  add_foreign_key "legislator_votes", "legislators"
  add_foreign_key "legislators", "addresses"
  add_foreign_key "legislators", "districts"
  add_foreign_key "passkeys", "users"
  add_foreign_key "user_addresses", "addresses"
  add_foreign_key "user_addresses", "users"
  add_foreign_key "user_districts", "districts"
  add_foreign_key "user_districts", "users"
  add_foreign_key "user_invites", "users"
  add_foreign_key "user_legislator_scores", "user_legislators"
  add_foreign_key "user_legislators", "legislators"
  add_foreign_key "user_legislators", "users"
  add_foreign_key "user_votes", "bills"
  add_foreign_key "user_votes", "users"
end
