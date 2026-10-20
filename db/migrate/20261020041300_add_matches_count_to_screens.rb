class AddMatchesCountToScreens < ActiveRecord::Migration[8.1]
  # A counter cache: screens.matches_count is kept up to date by Match (counter_cache: true),
  # so the history page can sort and filter by it without a COUNT query per row.
  def up
    add_column :screens, :matches_count, :integer, null: false, default: 0
    execute <<~SQL
      UPDATE screens SET matches_count = (SELECT COUNT(*) FROM matches WHERE matches.screen_id = screens.id)
    SQL
  end

  def down
    remove_column :screens, :matches_count
  end
end
