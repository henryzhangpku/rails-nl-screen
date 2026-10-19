class CreateMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :matches do |t|
      t.references :screen, null: false, foreign_key: true
      t.string :symbol, null: false
      t.json :details, null: false, default: []
      t.string :why, null: false

      t.timestamps
    end
  end
end
