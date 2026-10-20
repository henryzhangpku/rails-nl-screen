# This migration comes from prompt_engine (originally 20250806145043)
class InstallPromptEngine < ActiveRecord::Migration[8.0]
  def change
    create_table :prompt_engine_settings do |t|
      # Encrypted API keys
      t.text :openai_api_key
      t.text :anthropic_api_key
      # Other settings can be added here in the future
      t.json :preferences
      t.timestamps
    end

    create_table :prompt_engine_prompts do |t|
      t.string :name
      t.text :description
      t.text :content
      t.text :system_message
      t.string :model
      t.float :temperature
      t.integer :max_tokens
      t.string :status
      t.json :metadata
      t.integer :versions_count, default: 0, null: false
      t.string :slug
      t.timestamps
    end

    add_index :prompt_engine_prompts, :slug, unique: true

    create_table :prompt_engine_parameters do |t|
      t.references :prompt, null: false, foreign_key: {to_table: :prompt_engine_prompts}
      t.string :name, null: false
      t.text :description
      t.string :parameter_type, null: false, default: "string"
      t.boolean :required, null: false, default: true
      t.string :default_value
      t.json :validation_rules
      t.string :example_value
      t.integer :position
      t.timestamps
    end

    add_index :prompt_engine_parameters, [:prompt_id, :name], unique: true
    add_index :prompt_engine_parameters, :position

    create_table :prompt_engine_prompt_versions do |t|
      t.references :prompt, null: false, foreign_key: {to_table: :prompt_engine_prompts}
      t.integer :version_number, null: false
      t.text :content, null: false
      t.text :system_message
      t.string :model
      t.float :temperature
      t.integer :max_tokens
      t.json :metadata
      t.string :created_by
      t.text :change_description
      t.timestamps
    end

    add_index :prompt_engine_prompt_versions, [:prompt_id, :version_number], unique: true, name: "index_prompt_versions_on_prompt_and_version"
    add_index :prompt_engine_prompt_versions, :version_number

    create_table :prompt_engine_playground_run_results do |t|
      t.references :prompt_version, null: false, foreign_key: {to_table: :prompt_engine_prompt_versions}
      # API Provider and Model Info
      t.string :provider, null: false
      t.string :model, null: false
      # Prompt Details
      t.text :rendered_prompt, null: false
      t.text :system_message
      t.text :parameters
      # Response Details
      t.text :response, null: false
      t.float :execution_time, null: false
      t.integer :token_count
      # Settings Used
      t.float :temperature
      t.integer :max_tokens
      t.timestamps
    end

    add_index :prompt_engine_playground_run_results, :provider
    add_index :prompt_engine_playground_run_results, :created_at

    create_table :prompt_engine_eval_sets do |t|
      t.string :name, null: false
      t.text :description
      t.references :prompt, null: false, foreign_key: {to_table: :prompt_engine_prompts}
      t.string :openai_eval_id
      t.string :grader_type, default: "exact_match", null: false
      t.json :grader_config
      t.timestamps
    end

    add_index :prompt_engine_eval_sets, :openai_eval_id
    add_index :prompt_engine_eval_sets, :grader_type

    create_table :prompt_engine_test_cases do |t|
      t.references :eval_set, null: false, foreign_key: {to_table: :prompt_engine_eval_sets}
      t.json :input_variables, null: false
      t.text :expected_output, null: false
      t.text :description
      t.timestamps
    end

    create_table :prompt_engine_eval_runs do |t|
      t.references :eval_set, null: false, foreign_key: {to_table: :prompt_engine_eval_sets}
      t.references :prompt_version, null: false, foreign_key: {to_table: :prompt_engine_prompt_versions}
      t.integer :status, default: 0, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :total_count, default: 0
      t.integer :passed_count, default: 0
      t.integer :failed_count, default: 0
      t.text :error_message
      t.string :openai_run_id
      t.string :openai_file_id
      t.string :report_url
      t.timestamps
    end

    add_index :prompt_engine_eval_runs, :openai_run_id

    create_table :prompt_engine_eval_results do |t|
      t.references :eval_run, null: false, foreign_key: {to_table: :prompt_engine_eval_runs}
      t.references :test_case, null: false, foreign_key: {to_table: :prompt_engine_test_cases}
      t.text :actual_output
      t.boolean :passed, default: false
      t.integer :execution_time_ms
      t.text :error_message
      t.timestamps
    end

    add_index :prompt_engine_eval_sets, [:prompt_id, :name], unique: true
  end
end
