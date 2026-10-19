class CreateBars < ActiveRecord::Migration[8.1]
  def change
    create_table :bars do |t|
      t.string :symbol, null: false
      t.date :date, null: false
      t.float :open, :high, :low, :close, null: false
      t.integer :volume, limit: 8, null: false, default: 0

      t.timestamps
    end
    add_index :bars, [ :symbol, :date ], unique: true
  end
end
