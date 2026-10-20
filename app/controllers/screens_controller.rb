class ScreensController < ApplicationController
  allow_unauthenticated_access

  SORTS = %w[created_at matches_count query status].freeze

  # History: search, filter, sort and paginate inside the "screens" Turbo Frame.
  # Sort columns and directions are whitelisted, never interpolated into SQL.
  def index
    sort = params[:sort].presence_in(SORTS) || "created_at"
    direction = params[:direction].presence_in(%w[asc desc]) || "desc"

    @screens = Screen.matching(params[:q])
                     .with_status(params[:status])
                     .from_source(params[:source])
                     .with_matches(params[:with_matches])
                     .order(sort => direction, id: :desc)
                     .page(params[:page]).per(10)
  end

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

  # From the history table: remove the row and show a toast, without leaving the page.
  def destroy
    screen = Screen.find(params[:id])
    screen.destroy!
    toast = { "status" => "success", "message" => "Deleted “#{screen.query.truncate(60)}”" }

    respond_to do |format|
      format.turbo_stream do
        flash.now[:toast] = toast
        render turbo_stream: [ turbo_stream.remove(screen), turbo_stream.update("toast", partial: "shared/toast") ]
      end
      format.html { redirect_to screens_path, flash: { toast: toast } }
    end
  end
end
