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
      expect(page.css(".ns-chip").map(&:text)).to eq [ "RSI(14) below 30", "Price above SMA(200)" ]
    end

    it "re-renders the form when nothing was understood" do
      post screens_path, params: { screen: { query: "blah" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("couldn&#39;t turn that")
    end
  end
end
