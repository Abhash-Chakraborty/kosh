# Projects and trips. The index shows active ones (archived behind a toggle);
# a project's page shows its totals, breakdowns, transactions and IOUs, over
# every account the viewer can see or just one of them.
class ProjectsController < ApplicationController
  ENTRY_LIMIT = 200

  before_action :require_non_guest!, except: %i[index show]
  before_action :set_project, only: %i[show edit update destroy archive unarchive]

  def index
    @show_archived = params[:archived] == "1"
    projects = Current.family.projects.ordered
    @projects = (@show_archived ? projects.archived : projects.active).to_a
    @archived_count = Current.family.projects.archived.count
    @accounts = Current.user.accessible_accounts

    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t(".title"), nil ] ]
  end

  def show
    @accounts = Current.user.accessible_accounts.alphabetically.to_a
    @account = @accounts.find { |account| account.id == params[:account_id] } if params[:account_id].present?
    scope = @account ? Account.where(id: @account.id) : Current.user.accessible_accounts
    @totals = @project.totals(accounts: scope)
    @cost_sheet = Project::CostSheet.new(@totals)
    @entries = @project.entries_in(scope).limit(ENTRY_LIMIT + 1).to_a
    @more_entries = @entries.size > ENTRY_LIMIT
    @entries = @entries.first(ENTRY_LIMIT)
    @counted_entry_ids = @totals.entries.map(&:id).to_set
    @ious = @project.ious.includes(:account, :payments).by_due_date.to_a
    @ious = @ious.select { |iou| iou.account_id.nil? || iou.account_id == @account.id } if @account

    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("projects.index.title"), projects_path ], [ @project.name, nil ] ]
  end

  def new
    @project = Current.family.projects.new(kind: params[:kind].presence_in(Project::KINDS) || "project")
  end

  def create
    @project = Current.family.projects.new(project_params)

    if @project.save
      redirect_after_save(project_path(@project), t(".success"))
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_after_save(project_path(@project), t(".success"))
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def archive
    @project.archive!
    redirect_to project_path(@project), notice: t(".success"), status: :see_other
  end

  def unarchive
    @project.unarchive!
    redirect_to project_path(@project), notice: t(".success"), status: :see_other
  end

  def destroy
    @project.destroy!
    redirect_to projects_path, notice: t(".success"), status: :see_other
  end

  private
    def set_project
      @project = Current.family.projects.find(params[:id])
    end

    def project_params
      params.require(:project).permit(:name, :kind, :color, :lucide_icon, :start_on, :end_on, :budget, :currency, :notes)
    end

    def redirect_after_save(path, notice)
      flash[:notice] = notice
      respond_to do |format|
        format.html { redirect_to path }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, path) }
      end
    end
end
