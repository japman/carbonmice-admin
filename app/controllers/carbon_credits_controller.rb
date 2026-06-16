class CarbonCreditsController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: :index
  before_action -> { authorize!(:manage_master_data) }, except: :index

  def index
    page = params[:page].to_i.clamp(1, 10_000)
    rows = repo.list(user_id: params[:user_id].presence, page: page).to_a
    @has_next = rows.size > Persistence::ArCarbonCreditRepository::PAGE_SIZE
    @credits = rows.first(Persistence::ArCarbonCreditRepository::PAGE_SIZE)
    @page = page
    @users = Core::User.kept.order(:email)
  end

  def new
    @users   = Core::User.kept.order(:email)
    @sources = Core::CarbonOffsetSource.kept.order(:name)
  end

  def create
    result = MasterData::CreateCarbonCredit.call(actor: current_admin, attrs: create_params.to_h.symbolize_keys,
                                                 repo: repo, audit: audit)
    if result.success?
      redirect_to carbon_credits_path, notice: "เพิ่ม carbon credit แล้ว"
    else
      defaults = { user_id: nil, carbon_credit: nil, carbon_offset_source_id: nil }
      @credit = Data.define(*defaults.keys).new(**defaults.merge(create_params.to_h.symbolize_keys))
      @users   = Core::User.kept.order(:email)
      @sources = Core::CarbonOffsetSource.kept.order(:name)
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @credit  = repo.find(params[:id])
    @sources = Core::CarbonOffsetSource.kept.order(:name)
  rescue Ports::NotFound
    redirect_to carbon_credits_path, alert: "ไม่พบ carbon credit"
  end

  def update
    result = MasterData::UpdateCarbonCredit.call(actor: current_admin, id: params[:id],
                                                 attrs: update_params.to_h.symbolize_keys,
                                                 repo: repo, audit: audit)
    if result.success?
      redirect_to carbon_credits_path, notice: "บันทึกแล้ว"
    else
      @credit = repo.find(params[:id])
      @credit.assign_attributes(update_params.to_h)
      @sources = Core::CarbonOffsetSource.kept.order(:name)
      flash.now[:alert] = result.error
      render :edit, status: :unprocessable_entity
    end
  rescue Ports::NotFound
    redirect_to carbon_credits_path, alert: "ไม่พบ carbon credit"
  end

  def destroy
    result = MasterData::DeleteCarbonCredit.call(actor: current_admin, id: params[:id],
                                                 repo: repo, audit: audit)
    if result.success?
      redirect_to carbon_credits_path, notice: "ลบ carbon credit แล้ว (soft delete)"
    else
      redirect_to carbon_credits_path, alert: result.error
    end
  end

  private

    def create_params = params.require(:carbon_credit).permit(:user_id, :carbon_credit, :carbon_offset_source_id)
    def update_params = params.require(:carbon_credit).permit(:carbon_credit, :carbon_offset_source_id)
    def repo = Persistence::ArCarbonCreditRepository.new
end
