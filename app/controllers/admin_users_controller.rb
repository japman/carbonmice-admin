class AdminUsersController < ApplicationController
  before_action -> { authorize!(:manage_admin_users) }

  def index
    @admin_users = repo.all_ordered
  end

  def new
  end

  def create
    result = AdminAuth::CreateAdmin.call(actor: current_admin, repo: repo, audit: audit,
                                         attrs: create_params.to_h.symbolize_keys)
    if result.success?
      redirect_to admin_users_path, notice: "สร้างบัญชีผู้ดูแลแล้ว"
    else
      redirect_to new_admin_user_path, alert: result.error
    end
  end

  def edit
    @admin_user = repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to admin_users_path, alert: "ไม่พบบัญชีผู้ดูแล"
  end

  def update
    result = AdminAuth::UpdateAdmin.call(actor: current_admin, repo: repo, audit: audit,
                                         id: params[:id], attrs: update_params.to_h.symbolize_keys)
    if result.success?
      redirect_to admin_users_path, notice: "บันทึกการแก้ไขแล้ว"
    else
      redirect_to admin_users_path, alert: result.error
    end
  end

  private
    def create_params = params.require(:admin_user).permit(:email_address, :name, :password, :role)
    def update_params = params.require(:admin_user).permit(:name, :role, :active)
    def repo = Persistence::ArAdminUserRepository.new
    def audit = Persistence::ArAuditRecorder.new
end
