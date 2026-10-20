# Request specs sign in the way a browser does: through SessionsController.
module SignInHelper
  def sign_in_as(user, password: "password")
    post session_path, params: { email_address: user.email_address, password: password }
  end
end

RSpec.configure do |config|
  config.include SignInHelper, type: :request
end
