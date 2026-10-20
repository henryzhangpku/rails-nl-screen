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

ActiveRecord::Schema[8.1].define(version: 2026_10_20_055552) do
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

  create_table "prompt_engine_eval_results", force: :cascade do |t|
    t.integer "eval_run_id", null: false
    t.integer "test_case_id", null: false
    t.text "actual_output"
    t.boolean "passed", default: false
    t.integer "execution_time_ms"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["eval_run_id"], name: "index_prompt_engine_eval_results_on_eval_run_id"
    t.index ["test_case_id"], name: "index_prompt_engine_eval_results_on_test_case_id"
  end

  create_table "prompt_engine_eval_runs", force: :cascade do |t|
    t.integer "eval_set_id", null: false
    t.integer "prompt_version_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "total_count", default: 0
    t.integer "passed_count", default: 0
    t.integer "failed_count", default: 0
    t.text "error_message"
    t.string "openai_run_id"
    t.string "openai_file_id"
    t.string "report_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["eval_set_id"], name: "index_prompt_engine_eval_runs_on_eval_set_id"
    t.index ["openai_run_id"], name: "index_prompt_engine_eval_runs_on_openai_run_id"
    t.index ["prompt_version_id"], name: "index_prompt_engine_eval_runs_on_prompt_version_id"
  end

  create_table "prompt_engine_eval_sets", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "prompt_id", null: false
    t.string "openai_eval_id"
    t.string "grader_type", default: "exact_match", null: false
    t.json "grader_config"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["grader_type"], name: "index_prompt_engine_eval_sets_on_grader_type"
    t.index ["openai_eval_id"], name: "index_prompt_engine_eval_sets_on_openai_eval_id"
    t.index ["prompt_id", "name"], name: "index_prompt_engine_eval_sets_on_prompt_id_and_name", unique: true
    t.index ["prompt_id"], name: "index_prompt_engine_eval_sets_on_prompt_id"
  end

  create_table "prompt_engine_parameters", force: :cascade do |t|
    t.integer "prompt_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "parameter_type", default: "string", null: false
    t.boolean "required", default: true, null: false
    t.string "default_value"
    t.json "validation_rules"
    t.string "example_value"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_prompt_engine_parameters_on_position"
    t.index ["prompt_id", "name"], name: "index_prompt_engine_parameters_on_prompt_id_and_name", unique: true
    t.index ["prompt_id"], name: "index_prompt_engine_parameters_on_prompt_id"
  end

  create_table "prompt_engine_playground_run_results", force: :cascade do |t|
    t.integer "prompt_version_id", null: false
    t.string "provider", null: false
    t.string "model", null: false
    t.text "rendered_prompt", null: false
    t.text "system_message"
    t.text "parameters"
    t.text "response", null: false
    t.float "execution_time", null: false
    t.integer "token_count"
    t.float "temperature"
    t.integer "max_tokens"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_prompt_engine_playground_run_results_on_created_at"
    t.index ["prompt_version_id"], name: "idx_on_prompt_version_id_747dcd550d"
    t.index ["provider"], name: "index_prompt_engine_playground_run_results_on_provider"
  end

  create_table "prompt_engine_prompt_versions", force: :cascade do |t|
    t.integer "prompt_id", null: false
    t.integer "version_number", null: false
    t.text "content", null: false
    t.text "system_message"
    t.string "model"
    t.float "temperature"
    t.integer "max_tokens"
    t.json "metadata"
    t.string "created_by"
    t.text "change_description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["prompt_id", "version_number"], name: "index_prompt_versions_on_prompt_and_version", unique: true
    t.index ["prompt_id"], name: "index_prompt_engine_prompt_versions_on_prompt_id"
    t.index ["version_number"], name: "index_prompt_engine_prompt_versions_on_version_number"
  end

  create_table "prompt_engine_prompts", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.text "content"
    t.text "system_message"
    t.string "model"
    t.float "temperature"
    t.integer "max_tokens"
    t.string "status"
    t.json "metadata"
    t.integer "versions_count", default: 0, null: false
    t.string "slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_prompt_engine_prompts_on_slug", unique: true
  end

  create_table "prompt_engine_settings", force: :cascade do |t|
    t.text "openai_api_key"
    t.text "anthropic_api_key"
    t.json "preferences"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "prompt_engine_test_cases", force: :cascade do |t|
    t.integer "eval_set_id", null: false
    t.json "input_variables", null: false
    t.text "expected_output", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["eval_set_id"], name: "index_prompt_engine_test_cases_on_eval_set_id"
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

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "conditions", "screens"
  add_foreign_key "matches", "screens"
  add_foreign_key "prompt_engine_eval_results", "prompt_engine_eval_runs", column: "eval_run_id"
  add_foreign_key "prompt_engine_eval_results", "prompt_engine_test_cases", column: "test_case_id"
  add_foreign_key "prompt_engine_eval_runs", "prompt_engine_eval_sets", column: "eval_set_id"
  add_foreign_key "prompt_engine_eval_runs", "prompt_engine_prompt_versions", column: "prompt_version_id"
  add_foreign_key "prompt_engine_eval_sets", "prompt_engine_prompts", column: "prompt_id"
  add_foreign_key "prompt_engine_parameters", "prompt_engine_prompts", column: "prompt_id"
  add_foreign_key "prompt_engine_playground_run_results", "prompt_engine_prompt_versions", column: "prompt_version_id"
  add_foreign_key "prompt_engine_prompt_versions", "prompt_engine_prompts", column: "prompt_id"
  add_foreign_key "prompt_engine_test_cases", "prompt_engine_eval_sets", column: "eval_set_id"
  add_foreign_key "sessions", "users"
end
