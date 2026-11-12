# Renames a person on the Owed page. People aren't records: an IOU carries
# its person's name, so a rename rewrites the name on each of their IOUs.
# Transactions that earlier payments made keep the name they were given.
class IouPeopleController < ApplicationController
  before_action :require_non_guest!
  before_action :set_person

  def edit
  end

  def update
    @new_name = params.dig(:iou_person, :new_name).to_s.strip

    if @new_name.blank? || @new_name.length > 255
      @error = t(".invalid")
      render :edit, status: :unprocessable_entity
    else
      @ious.update_all(person: @new_name, updated_at: Time.current)
      flash[:notice] = t(".success", person: @new_name)
      respond_to do |format|
        format.html { redirect_to ious_path }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, ious_path) }
      end
    end
  end

  private
    def set_person
      @name = (params[:name].presence || params.dig(:iou_person, :name)).to_s.strip
      @ious = Current.family.ious.for_person(@name)
      @count = @ious.count
      head :not_found if @name.blank? || @count.zero?
    end
end
