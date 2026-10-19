class AddScoreToMatches < ActiveRecord::Migration[8.1]
  def change
    # Average "strength" of the conditions it passed (0..1); results are ranked by it.
    add_column :matches, :score, :float, null: false, default: 0.0
  end
end
