class CategoriesController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: :index
  before_action -> { authorize!(:manage_master_data) }, only: %i[edit update]

  def index
    @categories = repo.list
    @units = Core::Unit.kept.order(:code)
  end

  def edit
    @category = repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to categories_path, alert: "ไม่พบหมวดหมู่"
  end

  def update
    result = MasterData::RenameCategory.call(actor: current_admin, id: params[:id],
                                             name_thai: params.require(:category)[:name_thai],
                                             repo: repo, audit: audit)
    if result.success?
      redirect_to categories_path, notice: "บันทึกชื่อหมวดแล้ว"
    else
      redirect_to edit_category_path(params[:id]), alert: result.error
    end
  end

  private

    def repo = Persistence::ArCategoryRepository.new
    def audit = Persistence::ArAuditRecorder.new
end
