# Money people owe the family and money it owes, grouped by person. Payments
# are recorded through IouPaymentsController.
class IousController < ApplicationController
  before_action :require_non_guest!, except: :index
  before_action :set_iou, only: %i[edit update destroy]

  def index
    ious = Current.family.ious.includes(:account, :project, payments: { entry: :account }).by_due_date.to_a
    open_ious, @settled_ious = ious.partition { |iou| !iou.settled? }

    @open_groups = open_ious
      .group_by { |iou| iou.person.strip.downcase }
      .values
      .sort_by { |group| group.first.person.downcase }
    @settled_ious = @settled_ious.sort_by { |iou| iou.payments.map(&:date).max || iou.updated_at.to_date }.reverse

    currency = Current.family.primary_currency_code
    @owed_to_you, skipped_in = Iou.remaining_total(open_ious.select(&:owed_to_me?), currency: currency)
    @you_owe, skipped_out = Iou.remaining_total(open_ious.select(&:i_owe?), currency: currency)
    @unconverted_count = skipped_in + skipped_out

    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t(".title"), nil ] ]
  end

  def new
    @iou = Current.family.ious.new(
      direction: params[:direction].presence_in(Iou::DIRECTIONS) || "owed_to_me",
      currency: Current.family.primary_currency_code,
      project: Current.family.projects.find_by(id: params[:project_id].presence)
    )
    set_form_options
  end

  def create
    @iou = Current.family.ious.new(iou_params)

    if @iou.save
      redirect_after_save(t(".success"))
    else
      set_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    set_form_options
  end

  def update
    if @iou.update(iou_params)
      redirect_after_save(t(".success"))
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @iou.destroy!
    redirect_to ious_path, notice: t(".success"), status: :see_other
  end

  private
    def set_iou
      @iou = Current.family.ious.find(params[:id])
    end

    # Accounts are looked up inside what this user may see, so a crafted id
    # can't point an IOU at someone else's private account.
    def iou_params
      submitted = params.require(:iou)
      permitted = submitted.permit(:direction, :person, :description, :amount, :currency, :due_on, :notes)
      permitted[:account_id] = Current.user.accessible_accounts.find_by(id: submitted[:account_id].presence)&.id if submitted.key?(:account_id)
      permitted[:category_id] = Current.family.categories.find_by(id: submitted[:category_id].presence)&.id if submitted.key?(:category_id)
      permitted[:project_id] = Current.family.projects.find_by(id: submitted[:project_id].presence)&.id if submitted.key?(:project_id)
      permitted
    end

    def set_form_options
      @accounts = form_accounts
      @categories = Current.family.categories.alphabetically_by_hierarchy.to_a
      @projects = Current.family.projects.active.or(Current.family.projects.where(id: @iou.project_id)).ordered.to_a
      @people = Current.family.ious.distinct.order(:person).pluck(:person)
    end

    def form_accounts
      Current.user.accessible_accounts.active.alphabetically.includes(:account_providers, logo_attachment: :blob).to_a
    end

    # Back to the project's page when the IOU was added from there.
    def redirect_after_save(notice)
      flash[:notice] = notice
      path = params[:from_project].present? && @iou.project ? project_path(@iou.project) : ious_path
      respond_to do |format|
        format.html { redirect_to path }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, path) }
      end
    end
end
