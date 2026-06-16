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
                                             name_thai: params.require(:category).permit(:name_thai)[:name_thai],
                                             repo: repo, audit: audit)
    if result.success?
      @category = result.value
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "บันทึกชื่อหมวดแล้ว" }
        format.html { redirect_to categories_path, notice: "บันทึกชื่อหมวดแล้ว" }
      end
    else
      @category = repo.find(params[:id])
      @category.assign_attributes(name_thai: params.require(:category).permit(:name_thai)[:name_thai])
      flash.now[:alert] = result.error
      render :edit, status: :unprocessable_entity
    end
  rescue Ports::NotFound
    redirect_to categories_path, alert: "ไม่พบหมวดหมู่"
  end

  private

    def repo = Persistence::ArCategoryRepository.new
end
