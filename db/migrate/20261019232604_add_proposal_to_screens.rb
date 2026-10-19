class AddProposalToScreens < ActiveRecord::Migration[8.1]
  def change
    # Audit trail: exactly what the parser (or model) proposed, before validation.
    add_column :screens, :proposal, :json, null: false, default: {}
    add_column :screens, :parser, :string
  end
end
