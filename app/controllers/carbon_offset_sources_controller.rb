class CarbonOffsetSourcesController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: :index
  before_action -> { authorize!(:manage_master_data) }, except: :index

  def index
    @sources = repo.list
  end

  def new
  end

  def create
    result = MasterData::CreateCarbonOffsetSource.call(actor: current_admin, attrs: create_params.to_h.symbolize_keys,
                                                       repo: repo, audit: audit)
    if result.success?
      @source = result.value
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "สร้างแหล่งออฟเซ็ตแล้ว" }
        format.html { redirect_to carbon_offset_sources_path, notice: "สร้างแหล่งออฟเซ็ตแล้ว" }
      end
    else
      @source = Data.define(:name, :name_th).new(name: create_params[:name], name_th: create_params[:name_th])
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @source = repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to carbon_offset_sources_path, alert: "ไม่พบแหล่งออฟเซ็ต"
  end

  def update
    result = MasterData::RenameCarbonOffsetSource.call(actor: current_admin, id: params[:id],
                                                       name_th: update_params[:name_th],
                                                       repo: repo, audit: audit)
    if result.success?
      @source = result.value
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "บันทึกแล้ว" }
        format.html { redirect_to carbon_offset_sources_path, notice: "บันทึกแล้ว" }
      end
    else
      @source = repo.find(params[:id])
      @source.assign_attributes(name_th: update_params[:name_th])
      flash.now[:alert] = result.error
      render :edit, status: :unprocessable_entity
    end
  rescue Ports::NotFound
    redirect_to carbon_offset_sources_path, alert: "ไม่พบแหล่งออฟเซ็ต"
  end

  def destroy
    result = MasterData::DeleteCarbonOffsetSource.call(actor: current_admin, id: params[:id],
                                                       repo: repo, audit: audit)
    if result.success?
      @source = result.value
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "ลบแหล่งออฟเซ็ตแล้ว (soft delete)" }
        format.html { redirect_to carbon_offset_sources_path, notice: "ลบแหล่งออฟเซ็ตแล้ว (soft delete)" }
      end
    else
      redirect_to carbon_offset_sources_path, alert: result.error
    end
  end

  private

    def create_params = params.require(:carbon_offset_source).permit(:name, :name_th)
    def update_params = params.require(:carbon_offset_source).permit(:name_th)
    def repo = Persistence::ArCarbonOffsetSourceRepository.new
end
