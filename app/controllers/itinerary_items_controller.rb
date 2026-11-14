# A trip's plan, edited from the project's page: add, change and remove the
# lines of its itinerary.
class ItineraryItemsController < ApplicationController
  before_action :require_non_guest!
  before_action :set_project
  before_action :set_item, only: %i[edit update destroy]

  def new
    @item = @project.itinerary_items.new(
      kind: params[:kind].presence_in(ItineraryItem::KINDS) || "activity",
      starts_on: default_date
    )
  end

  def create
    @item = @project.itinerary_items.new(item_params)

    if @item.save
      redirect_after_save(t(".success"))
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @item.update(item_params)
      redirect_after_save(t(".success"))
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @item.destroy!
    redirect_to project_path(@project, anchor: "itinerary"), notice: t(".success"), status: :see_other
  end

  private
    def set_project
      @project = Current.family.projects.find(params[:project_id])
    end

    def set_item
      @item = @project.itinerary_items.find(params[:id])
    end

    def item_params
      params.require(:itinerary_item).permit(:kind, :title, :starts_on, :ends_on, :time_of_day, :location, :reference, :notes)
    end

    # The day asked for, else the day after the plan's last line, else the
    # trip's first day.
    def default_date
      requested = Date.iso8601(params[:date].to_s) rescue nil
      requested || @project.itinerary_items.maximum(:starts_on) || @project.start_on || Date.current
    end

    def redirect_after_save(notice)
      flash[:notice] = notice
      path = project_path(@project, anchor: "itinerary")
      respond_to do |format|
        format.html { redirect_to path }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, path) }
      end
    end
end
