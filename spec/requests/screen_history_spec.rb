require "rails_helper"

RSpec.describe "Screen history", type: :request do
  def rows = Nokogiri::HTML(response.body).css("#screens tbody tr")
  def queries = rows.map { |row| row.at(".ns-history__link").text }

  describe "GET /screens" do
    it "lists screens newest first, inside the screens Turbo Frame" do
      create(:screen, query: "RSI under 30", created_at: 2.days.ago)
      create(:screen, query: "MACD crossing up", created_at: 1.day.ago)

      get screens_path

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at("turbo-frame#screens")).to be_present
      expect(queries).to eq [ "MACD crossing up", "RSI under 30" ]
    end

    it "searches the query text" do
      create(:screen, query: "RSI under 30")
      create(:screen, query: "MACD crossing up")

      get screens_path(q: "macd")

      expect(queries).to eq [ "MACD crossing up" ]
    end

    it "filters by status, parser and whether there are matches" do
      create(:screen, query: "done, rules, none")
      create(:screen, :running, query: "running")
      create(:screen, :from_claude, query: "claude")
      create(:screen, :with_matches, query: "has matches")

      get screens_path(status: "running")
      expect(queries).to eq [ "running" ]

      get screens_path(source: "claude")
      expect(queries).to eq [ "claude" ]

      get screens_path(with_matches: "1")
      expect(queries).to eq [ "has matches" ]
    end

    it "ignores filter values outside the allowed lists" do
      create(:screen)
      get screens_path(status: "'; DROP TABLE screens; --", source: "nope")
      expect(rows.size).to eq 1
    end

    it "sorts by an allowed column and direction" do
      create(:screen, :with_matches, matches: 1, query: "one")
      create(:screen, :with_matches, matches: 3, query: "three")

      get screens_path(sort: "matches_count", direction: "desc")

      expect(queries).to eq [ "three", "one" ]
    end

    it "falls back to the default order for an unknown sort column" do
      create(:screen, query: "older", created_at: 2.days.ago)
      create(:screen, query: "newer", created_at: 1.day.ago)

      get screens_path(sort: "id; DROP TABLE screens", direction: "sideways")

      expect(queries).to eq [ "newer", "older" ]
    end

    it "paginates ten per page with page links that advance the URL" do
      create_list(:screen, 12)

      get screens_path
      expect(rows.size).to eq 10
      link = Nokogiri::HTML(response.body).at(".ns-pager a[rel=next]")
      expect(link["data-turbo-action"]).to eq "advance"

      get screens_path(page: 2)
      expect(rows.size).to eq 2
    end
  end

  describe "DELETE /screens/:id" do
    let!(:screen) { create(:screen, :with_matches, query: "RSI under 30") }

    it "removes the row and shows a toast with Turbo Streams" do
      delete screen_path(screen), as: :turbo_stream

      expect(response.media_type).to eq Mime[:turbo_stream]
      expect(response.body).to include(%(<turbo-stream action="remove" target="#{ActionView::RecordIdentifier.dom_id(screen)}">))
      expect(response.body).to include(%(<turbo-stream action="update" target="toast">))
      expect(response.body).to include("Deleted “RSI under 30”")
      expect(Screen.exists?(screen.id)).to be false
      expect(Match.where(screen_id: screen.id)).to be_empty
    end

    it "redirects back to history with a toast for plain HTML requests" do
      delete screen_path(screen)

      expect(response).to redirect_to(screens_path)
      follow_redirect!
      expect(response.body).to include("Deleted “RSI under 30”")
    end
  end
end
