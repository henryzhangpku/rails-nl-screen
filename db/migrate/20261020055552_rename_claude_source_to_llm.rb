# Model proposals are no longer Claude-only: any RubyLLM provider can propose.
class RenameClaudeSourceToLlm < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE screens SET source = 'llm' WHERE source = 'claude'"
  end

  def down
    execute "UPDATE screens SET source = 'claude' WHERE source = 'llm'"
  end
end
