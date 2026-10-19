class ScreensController < ApplicationController
  def new
    @screen = Screen.new
    @recent = Screen.order(id: :desc).limit(5)
  end

  def create
    @screen = Screen.from_query(params.expect(screen: [ :query ])[:query])
    if @screen.save
      RunScreenJob.perform_later(@screen)
      redirect_to @screen
    else
      @recent = Screen.order(id: :desc).limit(5)
      render :new, status: :unprocessable_content
    end
  end

  def show
    @screen = Screen.includes(:conditions, :matches).find(params[:id])
  end
end
