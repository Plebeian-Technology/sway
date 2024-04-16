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

ActiveRecord::Schema[7.1].define(version: 2024_04_16_173249) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "addresses", force: :cascade do |t|
    t.string "street", null: false
    t.string "street_2"
    t.string "street_3"
    t.string "city", null: false
    t.string "state_province_code", null: false
    t.string "postal_code", null: false
    t.string "country", default: "US", null: false
    t.float "latitude"
    t.float "longitude"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "bill_cosponsors", force: :cascade do |t|
    t.bigint "legislator_id", null: false
    t.bigint "bill_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_bill_cosponsors_on_bill_id"
    t.index ["legislator_id"], name: "index_bill_cosponsors_on_legislator_id"
  end

  create_table "bill_score_districts", force: :cascade do |t|
    t.bigint "bill_score_id", null: false
    t.bigint "district_id", null: false
    t.integer "for"
    t.integer "against"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_score_id"], name: "index_bill_score_districts_on_bill_score_id"
    t.index ["district_id"], name: "index_bill_score_districts_on_district_id"
  end

  create_table "bill_scores", force: :cascade do |t|
    t.bigint "bill_id", null: false
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
    t.bigint "sponsor_id", null: false
    t.bigint "sway_locale_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sponsor_id"], name: "index_bills_on_sponsor_id"
    t.index ["sway_locale_id"], name: "index_bills_on_sway_locale_id"
  end

  create_table "districts", force: :cascade do |t|
    t.string "name"
    t.bigint "sway_locale_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sway_locale_id"], name: "index_districts_on_sway_locale_id"
  end

  create_table "legislator_votes", force: :cascade do |t|
    t.bigint "legislator_id", null: false
    t.bigint "bill_id", null: false
    t.string "support"
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
    t.bigint "address_id", null: false
    t.bigint "district_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["address_id"], name: "index_legislators_on_address_id"
    t.index ["district_id"], name: "index_legislators_on_district_id"
  end

  create_table "sway_locales", force: :cascade do |t|
    t.string "city"
    t.string "state"
    t.string "country"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_districts", force: :cascade do |t|
    t.bigint "district_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["district_id"], name: "index_user_districts_on_district_id"
    t.index ["user_id"], name: "index_user_districts_on_user_id"
  end

  create_table "user_legislator_scores", force: :cascade do |t|
    t.bigint "user_legislator_id", null: false
    t.integer "count_agreed"
    t.integer "count_disagreed"
    t.integer "count_no_legislator_vote"
    t.integer "count_legislator_abstained"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_legislator_id"], name: "index_user_legislator_scores_on_user_legislator_id"
  end

  create_table "user_legislators", force: :cascade do |t|
    t.bigint "legislator_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["legislator_id"], name: "index_user_legislators_on_legislator_id"
    t.index ["user_id"], name: "index_user_legislators_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "password_bcrypt"
    t.string "email"
    t.boolean "is_email_verified"
    t.string "phone"
    t.boolean "is_phone_verified"
    t.boolean "is_registration_complete"
    t.boolean "is_registered_to_vote"
    t.boolean "is_admin", default: false
    t.datetime "last_login_utc"
    t.bigint "address_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["address_id"], name: "index_users_on_address_id"
  end

  create_table "votes", force: :cascade do |t|
    t.datetime "voted_on_utc"
    t.bigint "bill_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_votes_on_bill_id"
  end

  add_foreign_key "bill_cosponsors", "bills"
  add_foreign_key "bill_cosponsors", "legislators"
  add_foreign_key "bill_score_districts", "bill_scores"
  add_foreign_key "bill_score_districts", "districts"
  add_foreign_key "bill_scores", "bills"
  add_foreign_key "bills", "legislators", column: "sponsor_id"
  add_foreign_key "bills", "sway_locales"
  add_foreign_key "districts", "sway_locales"
  add_foreign_key "legislator_votes", "bills"
  add_foreign_key "legislator_votes", "legislators"
  add_foreign_key "legislators", "addresses"
  add_foreign_key "legislators", "districts"
  add_foreign_key "user_districts", "districts"
  add_foreign_key "user_districts", "users"
  add_foreign_key "user_legislator_scores", "user_legislators"
  add_foreign_key "user_legislators", "legislators"
  add_foreign_key "user_legislators", "users"
  add_foreign_key "users", "addresses"
  add_foreign_key "votes", "bills"
end
