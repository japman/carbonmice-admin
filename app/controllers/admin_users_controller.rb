class AdminUsersController < ApplicationController
  before_action -> { authorize!(:manage_admin_users) }

  def index
    @admin_users = repo.list(search: params[:search].presence)
  end

  def new
    @admin_user = AdminUser.new
  end

  def create
    result = AdminAuth::CreateAdmin.call(actor: current_admin, repo: repo, audit: audit,
                                         attrs: create_params.to_h.symbolize_keys)
    if result.success?
      @admin_user = result.value
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "สร้างบัญชีผู้ดูแลแล้ว" }
        format.html { redirect_to admin_users_path, notice: "สร้างบัญชีผู้ดูแลแล้ว" }
      end
    else
      @admin_user = AdminUser.new(create_params.except(:password).to_h.symbolize_keys)
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_entity
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
      @admin_user = repo.find(params[:id])
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "บันทึกการแก้ไขแล้ว" }
        format.html { redirect_to admin_users_path, notice: "บันทึกการแก้ไขแล้ว" }
      end
    else
      @admin_user = repo.find(params[:id])
      @admin_user.assign_attributes(update_params.to_h)
      flash.now[:alert] = result.error
      render :edit, status: :unprocessable_entity
    end
  rescue Ports::NotFound
    redirect_to admin_users_path, alert: "ไม่พบบัญชีผู้ดูแล"
  end

  private
    def create_params = params.require(:admin_user).permit(:email_address, :name, :password, :role)
    def update_params = params.require(:admin_user).permit(:name, :role, :active)
    def repo = Persistence::ArAdminUserRepository.new
end
