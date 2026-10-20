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

ActiveRecord::Schema[8.1].define(version: 2026_10_20_041300) do
  create_table "bars", force: :cascade do |t|
    t.string "symbol", null: false
    t.date "date", null: false
    t.float "open", null: false
    t.float "high", null: false
    t.float "low", null: false
    t.float "close", null: false
    t.integer "volume", limit: 8, default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["symbol", "date"], name: "index_bars_on_symbol_and_date", unique: true
  end

  create_table "conditions", force: :cascade do |t|
    t.integer "screen_id", null: false
    t.string "indicator", null: false
    t.string "timeframe", default: "daily", null: false
    t.string "operator", null: false
    t.integer "period"
    t.float "value"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["screen_id"], name: "index_conditions_on_screen_id"
  end

  create_table "matches", force: :cascade do |t|
    t.integer "screen_id", null: false
    t.string "symbol", null: false
    t.json "details", default: [], null: false
    t.string "why", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "score", default: 0.0, null: false
    t.index ["screen_id"], name: "index_matches_on_screen_id"
  end

  create_table "screens", force: :cascade do |t|
    t.text "query", null: false
    t.string "source", default: "rules", null: false
    t.string "status", default: "pending", null: false
    t.integer "scanned_count", default: 0, null: false
    t.integer "universe_size", default: 0, null: false
    t.string "error_message"
    t.json "notes", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "proposal", default: {}, null: false
    t.string "parser"
    t.integer "matches_count", default: 0, null: false
  end

  add_foreign_key "conditions", "screens"
  add_foreign_key "matches", "screens"
end
