# The list of symbols a screen runs over (db/universe.txt).
module Universe
  FILE = Rails.root.join("db/universe.txt")

  def self.symbols
    FILE.readlines(chomp: true).map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
  end
end
