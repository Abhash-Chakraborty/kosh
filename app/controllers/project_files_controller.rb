# Files kept with a project or a trip: tickets, bookings, pictures, receipts.
class ProjectFilesController < ApplicationController
  before_action :require_non_guest!
  before_action :set_project

  def create
    uploads = Array(params.dig(:project, :files)).reject(&:blank?)
    return redirect_to(files_section_path, alert: t(".none_selected"), status: :see_other) if uploads.empty?

    problems = @project.with_lock do
      before = @project.files.pluck(:id)
      @project.files.attach(uploads)
      next if @project.valid?

      messages = @project.errors.full_messages_for(:files)
      # Take back whatever this upload saved before it was found invalid.
      @project.files.select { |file| file.persisted? && before.exclude?(file.id) }.each(&:purge)
      messages
    end

    if problems
      redirect_to files_section_path, alert: problems.to_sentence, status: :see_other
    else
      redirect_to files_section_path, notice: t(".success", count: uploads.size), status: :see_other
    end
  end

  def destroy
    @project.files.find(params[:id]).purge
    redirect_to files_section_path, notice: t(".success"), status: :see_other
  end

  private
    def set_project
      @project = Current.family.projects.find(params[:project_id])
    end

    def files_section_path
      project_path(@project, anchor: "files")
    end
end
