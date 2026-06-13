class PricingTiersController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: :index
  before_action -> { authorize!(:manage_master_data) }, except: :index

  def index
    @event_tiers = event_repo.list
    @offset_sources = Core::CarbonOffsetSource.kept.order(:name)
    @offset_tiers_by_source = offset_repo.list.group_by(&:carbon_offset_source_id)
  end

  def edit_event
    @tier = event_repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to pricing_tiers_path, alert: "ไม่พบระดับราคา"
  end

  def update_event
    result = ActiveRecord::Base.transaction do
      MasterData::UpdateEventPricingTier.call(actor: current_admin, id: params[:id],
                                              attrs: tier_params(:min_participants, :max_participants, :price_per_person),
                                              repo: event_repo, audit: audit)
    end
    if result.success?
      redirect_to pricing_tiers_path, notice: "บันทึกระดับราคาแล้ว"
    else
      redirect_to edit_event_pricing_tier_path(params[:id]), alert: result.error
    end
  end

  def edit_offset
    @tier = offset_repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to pricing_tiers_path, alert: "ไม่พบระดับราคา"
  end

  def update_offset
    result = ActiveRecord::Base.transaction do
      MasterData::UpdateOffsetPricingTier.call(actor: current_admin, id: params[:id],
                                               attrs: tier_params(:min_emission, :max_emission, :price_per_emission),
                                               repo: offset_repo, audit: audit)
    end
    if result.success?
      redirect_to pricing_tiers_path, notice: "บันทึกระดับราคาแล้ว"
    else
      redirect_to edit_offset_pricing_tier_path(params[:id]), alert: result.error
    end
  end

  private

    def tier_params(*keys) = params.require(:tier).permit(*keys).to_h.symbolize_keys
    def event_repo = Persistence::ArEventPricingTierRepository.new
    def offset_repo = Persistence::ArOffsetPricingTierRepository.new
    def audit = Persistence::ArAuditRecorder.new
end
