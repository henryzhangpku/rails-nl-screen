class CreateScreens < ActiveRecord::Migration[8.1]
  def change
    create_table :screens do |t|
      t.text :query, null: false
      t.string :source, null: false, default: "rules"
      t.string :status, null: false, default: "pending"
      t.integer :scanned_count, null: false, default: 0
      t.integer :universe_size, null: false, default: 0
      t.string :error_message
      t.json :notes, null: false, default: []

      t.timestamps
    end
  end
end
