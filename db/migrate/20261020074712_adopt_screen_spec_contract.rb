# Conditions move to the screen-spec contract shared with EquityScout: a whitelisted
# field, an operator, and a value or a reference field ({field: "rsi14", op: "<",
# value: 30}). Screens keep the whole validated spec and the funnel of each run;
# matches get their rank.
#
# Existing conditions are converted where the contract has the same rule. The rest
# (EMA, a MACD cross down, an RSI other than 14, a weekly moving average...) have no
# field, so they are removed and listed in the spec as not screened, with the reason.
class AdoptScreenSpecContract < ActiveRecord::Migration[8.1]
  OPS = { "above" => ">", "below" => "<" }.freeze

  def up
    add_column :conditions, :field, :string
    add_column :conditions, :op, :string
    add_column :conditions, :ref, :string
    add_column :conditions, :threshold, :json
    add_column :screens, :spec, :json, default: {}, null: false
    add_column :screens, :funnel, :json, default: [], null: false
    add_column :matches, :rank, :integer
    change_column_default :matches, :details, from: [], to: {}

    select_rows("SELECT id, query FROM screens").each do |screen_id, query|
      kept, unmapped = [], []
      select_rows("SELECT id, indicator, timeframe, operator, period, value FROM conditions WHERE screen_id = #{screen_id} ORDER BY position")
        .each do |id, indicator, timeframe, operator, period, value|
          if (condition = convert(indicator, timeframe, operator, period, value))
            kept << condition
            update "UPDATE conditions SET field = #{quote(condition["field"])}, op = #{quote(condition["op"])}, " \
                   "ref = #{quote(condition["ref"])}, threshold = #{quote(condition.key?("value") ? condition["value"].to_json : nil)} " \
                   "WHERE id = #{id}"
          else
            text = "#{timeframe} #{indicator}#{"(#{period})" if period} #{operator} #{value}".strip
            unmapped << { "text" => text, "reason" => "the shared screen spec has no field for this; removed when this app moved to it" }
            delete "DELETE FROM conditions WHERE id = #{id}"
          end
        end
      spec = { "version" => 1, "observation" => query, "universe" => {}, "conditions" => kept,
               "rank" => default_rank(kept), "top_n" => 5, "unmapped" => unmapped, "notes" => "" }
      update "UPDATE screens SET spec = #{quote(spec.to_json)} WHERE id = #{screen_id}"
      # Old matches keep the order they were ranked in (their old score); their details were in the old shape.
      select_values("SELECT id FROM matches WHERE screen_id = #{screen_id} ORDER BY score DESC, id").each.with_index(1) do |id, rank|
        update "UPDATE matches SET details = '{}', rank = #{rank} WHERE id = #{id}"
      end
    end

    remove_column :conditions, :indicator
    remove_column :conditions, :timeframe
    remove_column :conditions, :operator
    remove_column :conditions, :period
    remove_column :conditions, :value
    rename_column :conditions, :threshold, :value
    change_column_null :conditions, :field, false
    change_column_null :conditions, :op, false
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private
    def convert(indicator, timeframe, operator, period, value)
      weekly = timeframe == "weekly"
      case indicator
      when "rsi"
        { "field" => weekly ? "rsi14_w" : "rsi14", "op" => OPS[operator], "value" => value } if (period || 14) == 14
      when "macd"
        { "field" => weekly ? "macd_cross_up_w" : "macd_cross_up", "op" => "==", "value" => true } if operator == "crosses_up"
      when "sma"
        { "field" => "close", "op" => OPS[operator], "ref" => "sma#{period}" } if !weekly && period.in?([ 20, 50, 200 ])
      when "volume"
        { "field" => "volume_ratio_#{period}d", "op" => OPS[operator], "value" => value || 1.0 } if !weekly && period.in?([ 20, 50 ])
      when "drawdown"
        # "below 5" (within 5% of the high) is drawdown_52w >= -0.05; "above 20" is <= -0.20.
        { "field" => "drawdown_52w", "op" => operator == "below" ? ">=" : "<=", "value" => -value / 100.0 } unless weekly
      when "price"
        { "field" => "close", "op" => OPS[operator], "value" => value } unless weekly
      end
    end

    # Same rule as ScreenSpec.default_rank, frozen here as it was when this ran.
    def default_rank(conditions)
      rank = conditions.filter_map do |c|
        if c["ref"]&.match?(/\Asma\d+\z/) then { "field" => "pct_vs_#{c["ref"]}", "direction" => c["op"].start_with?(">") ? "desc" : "asc", "weight" => 1 }
        elsif c["value"].is_a?(Numeric) && c["op"].in?(%w[< <= > >=])
          { "field" => c["field"], "direction" => c["op"].start_with?(">") ? "desc" : "asc", "weight" => 1 }
        end
      end
      rank.uniq { _1["field"] }.presence || [ { "field" => "avg_dollar_volume_50d", "direction" => "desc", "weight" => 1 } ]
    end
end
