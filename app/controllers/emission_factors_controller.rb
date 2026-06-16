class EmissionFactorsController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: :index
  before_action -> { authorize!(:manage_master_data) }, except: :index

  def index
    page = params[:page].to_i.clamp(1, 10_000)
    rows = repo.list(search: params[:search].presence,
                     category_id: params[:category_id].presence, page: page).to_a
    @has_next = rows.size > Persistence::ArEmissionFactorRepository::PAGE_SIZE
    @factors = rows.first(Persistence::ArEmissionFactorRepository::PAGE_SIZE)
    @page = page
    @categories = Core::CarbonCategory.kept.order(:name_eng)
  end

  def new
    @categories = Core::CarbonCategory.kept.order(:name_eng)
  end

  def create
    result = MasterData::CreateEmissionFactor.call(actor: current_admin, repo: repo, audit: audit,
                                                   attrs: factor_params.to_h.symbolize_keys)
    if result.success?
      redirect_to emission_factors_path, notice: "สร้างค่า EF แล้ว"
    else
      defaults = { identifier: nil, name: nil, description: nil, source: nil,
                   value_per_unit: nil, unit_title: nil, carbon_category_id: nil }
      @factor = Data.define(*defaults.keys).new(**defaults.merge(factor_params.to_h.symbolize_keys))
      @categories = Core::CarbonCategory.kept.order(:name_eng)
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @factor = repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to emission_factors_path, alert: "ไม่พบค่า EF"
  end

  def update
    result = MasterData::UpdateEmissionFactor.call(actor: current_admin, id: params[:id],
                                                   repo: repo, audit: audit,
                                                   attrs: update_params.to_h.symbolize_keys)
    if result.success?
      redirect_to emission_factors_path, notice: "บันทึกการแก้ไขแล้ว"
    else
      @factor = repo.find(params[:id])
      @factor.assign_attributes(update_params.to_h)
      flash.now[:alert] = result.error
      render :edit, status: :unprocessable_entity
    end
  rescue Ports::NotFound
    redirect_to emission_factors_path, alert: "ไม่พบค่า EF"
  end

  def destroy
    result = MasterData::DeleteEmissionFactor.call(actor: current_admin, id: params[:id],
                                                   repo: repo, audit: audit)
    if result.success?
      redirect_to emission_factors_path, notice: "ลบค่า EF แล้ว (soft delete)"
    else
      redirect_to emission_factors_path, alert: result.error
    end
  end

  private
    def factor_params = params.require(:emission_factor)
                              .permit(:identifier, :name, :description, :source,
                                      :value_per_unit, :unit_title, :carbon_category_id)
    def update_params = params.require(:emission_factor)
                              .permit(:name, :description, :source, :value_per_unit, :unit_title)
    def repo = Persistence::ArEmissionFactorRepository.new
end
