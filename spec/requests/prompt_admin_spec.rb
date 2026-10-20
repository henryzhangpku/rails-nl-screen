require "rails_helper"

# PromptEngine's admin is mounted behind the Rails 8 generated sign-in.
RSpec.describe "Prompt admin", type: :request do
  let!(:user) { create(:user, email_address: "admin@example.com", password: "s3cret-pass") }

  def sign_in(password: "s3cret-pass")
    post session_path, params: { email_address: "admin@example.com", password: password }
  end

  it "sends anonymous visitors to the sign-in page" do
    get "/prompts/prompts"
    expect(response).to redirect_to(new_session_path)
    expect(response).to have_http_status(:found)
  end

  it "lets a signed-in user in, landing on the prompt editor" do
    sign_in
    expect(response).to redirect_to("http://www.example.com/prompts")

    get "/prompts/prompts"
    expect(response).to have_http_status(:ok)
  end

  it "rejects a wrong password" do
    sign_in(password: "nope")
    expect(response).to redirect_to(new_session_path)

    get "/prompts/prompts"
    expect(response).to redirect_to(new_session_path)
  end

  it "closes the admin again on sign out" do
    sign_in
    delete session_path
    expect(user.sessions.count).to eq 0

    get "/prompts/prompts"
    expect(response).to redirect_to(new_session_path)
  end

  it "keeps the screens public" do
    get screens_path
    expect(response).to have_http_status(:ok)
  end
end
