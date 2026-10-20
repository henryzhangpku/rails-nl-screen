# A screen matches each symbol at most once. Re-running a screen used to add a
# second row per symbol, so keep the first of any duplicates and recount.
class AddUniqueIndexOnMatchesScreenIdAndSymbol < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DELETE FROM matches WHERE id NOT IN (SELECT MIN(id) FROM matches GROUP BY screen_id, symbol)
    SQL
    execute <<~SQL
      UPDATE screens SET matches_count = (SELECT COUNT(*) FROM matches WHERE matches.screen_id = screens.id)
    SQL

    # The new index starts with screen_id, so it also serves the old one's lookups.
    remove_index :matches, :screen_id
    add_index :matches, %i[screen_id symbol], unique: true
  end

  def down
    remove_index :matches, %i[screen_id symbol]
    add_index :matches, :screen_id
  end
end
