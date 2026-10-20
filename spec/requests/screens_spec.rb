require "rails_helper"

RSpec.describe "Screens", type: :request do
  describe "GET /" do
    it "shows the query form" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="screen[query]"')
    end
  end

  describe "POST /screens" do
    it "parses the query, enqueues the scan, and shows what was understood" do
      expect {
        post screens_path, params: { screen: { query: "RSI(14) under 30, price above the 200-day moving average" } }
      }.to have_enqueued_job(RunScreenJob)

      follow_redirect!
      page = Nokogiri::HTML(response.body)
      expect(page.at("h1").text).to eq "Here's what I understood"
      expect(page.css(".ns-chip").map(&:text)).to eq [ "Daily RSI (14) under 30", "Price above its 200-day average" ]
    end

    it "re-renders the form when nothing was understood" do
      post screens_path, params: { screen: { query: "blah" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("couldn&#39;t turn that")
    end

    it "says why when what was understood can't be screened here" do
      post screens_path, params: { screen: { query: "price above the 21-day EMA" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("there is no EMA field")
    end

    it "is rate limited to 10 a minute per IP" do
      # The test environment's cache is a null store; count in memory instead.
      store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails.cache).to receive(:increment) { |*args, **options| store.increment(*args, **options) }

      10.times { post screens_path, params: { screen: { query: "RSI under 30" } } }
      expect(response).to redirect_to(screen_path(Screen.last))

      expect {
        post screens_path, params: { screen: { query: "RSI under 30" } }
      }.not_to change(Screen, :count)
      expect(response).to redirect_to(new_screen_path)
      expect(flash[:toast]).to include("message" => /Too many screens/)
    end
  end
end
