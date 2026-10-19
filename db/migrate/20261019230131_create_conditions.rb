class CreateConditions < ActiveRecord::Migration[8.1]
  def change
    create_table :conditions do |t|
      t.references :screen, null: false, foreign_key: true
      t.string :indicator, null: false
      t.string :timeframe, null: false, default: "daily"
      t.string :operator, null: false
      t.integer :period
      t.float :value
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
