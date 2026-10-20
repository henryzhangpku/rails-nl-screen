# build(:screen), create(:screen, :with_matches) etc. without the FactoryBot. prefix.
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
