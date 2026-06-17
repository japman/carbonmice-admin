class AppUsersController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: :index
  before_action -> { authorize!(:manage_app_users) }, only: %i[edit update]

  def index
    page = params[:page].to_i.clamp(1, 10_000)
    rows = repo.list(search: params[:search].presence, page: page).to_a
    @has_next = rows.size > Persistence::ArAppUserRepository::PAGE_SIZE
    @app_users = rows.first(Persistence::ArAppUserRepository::PAGE_SIZE)
    @credit_totals = credit_totals_for(@app_users.map(&:id))
    @page = page
  end

  def edit
    @app_user = repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to app_users_path, alert: "ไม่พบผู้ใช้งาน"
  end

  # Role and quota changes are independent audited use cases; only the
  # fields that actually changed run (no audit noise for no-ops).
  def update
    current = repo.find(params[:id])
    errors = []

    if update_params[:role].present? && update_params[:role] != current.role
      result = AppUsers::ChangeRole.call(actor: current_admin, id: params[:id],
                                         role: update_params[:role], repo: repo, audit: audit)
      errors << result.error if result.failure?
    end

    if update_params[:event_quota].present? && update_params[:event_quota].to_s != current.event_quota.to_s
      result = AppUsers::AdjustQuota.call(actor: current_admin, id: params[:id],
                                          quota: update_params[:event_quota], repo: repo, audit: audit)
      errors << result.error if result.failure?
    end

    if errors.empty?
      @app_user = repo.find(params[:id])
      @credit_totals = credit_totals_for([ @app_user.id ])
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "บันทึกการแก้ไขแล้ว" }
        format.html { redirect_to app_users_path, notice: "บันทึกการแก้ไขแล้ว" }
      end
    else
      @app_user = repo.find(params[:id])
      @app_user.assign_attributes(update_params.to_h) # re-show submitted values (won't persist)
      flash.now[:alert] = errors.join(" / ")
      render :edit, status: :unprocessable_entity
    end
  rescue Ports::NotFound
    redirect_to app_users_path, alert: "ไม่พบผู้ใช้งาน"
  end

  private
    def update_params = params.require(:app_user).permit(:role, :event_quota)
    def repo = Persistence::ArAppUserRepository.new

    # user_id => summed kept carbon_credit, in one grouped query (avoids N+1).
    def credit_totals_for(ids)
      Core::CarbonCredit.kept.where(user_id: ids).group(:user_id).sum(:carbon_credit)
    end
end
