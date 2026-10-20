require "test_helper"

class ScreensControllerTest < ActionDispatch::IntegrationTest
  test "new" do
    get root_path
    assert_response :success
    assert_select "textarea[name='screen[query]']"
  end

  test "create parses, enqueues the job and shows what was understood" do
    assert_enqueued_with(job: RunScreenJob) do
      post screens_path, params: { screen: { query: "RSI(14) under 30, price above the 200-day moving average" } }
    end
    follow_redirect!
    assert_select "h1", "Here's what I understood"
    assert_equal [ "RSI(14) below 30", "Price above SMA(200)" ], css_select(".chip").map(&:text)
  end

  test "create with nonsense re-renders the form" do
    post screens_path, params: { screen: { query: "blah" } }
    assert_response :unprocessable_content
    assert_select ".error", /couldn't turn that/
  end
end
