class EventsController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: %i[index show]
  before_action -> { authorize!(:manage_events) }, only: %i[edit update status]
  before_action :load_event, only: %i[show edit]

  def index
    page = params[:page].to_i.clamp(1, 10_000)
    rows = repo.list(search: params[:search].presence, status: params[:status].presence, page: page).to_a
    @has_next = rows.size > Persistence::ArEventRepository::PAGE_SIZE
    @events = rows.first(Persistence::ArEventRepository::PAGE_SIZE)
    @page = page
    @statuses = Core::EventStatus.ordered
  end

  def show
    @emissions = Core::CarbonEmission.where(event_id: @event.id)
                                     .includes(:carbon_category, :unit)
    @statuses = Core::EventStatus.ordered
  end

  def edit
  end

  def update
    result = Events::UpdateDetails.call(actor: current_admin, id: params[:id],
                                        attrs: update_params.to_h.symbolize_keys,
                                        repo: repo, audit: audit)
    if result.success?
      redirect_to event_path(params[:id]), notice: "บันทึกการแก้ไขแล้ว"
    else
      redirect_to edit_event_path(params[:id]), alert: result.error
    end
  rescue Ports::NotFound
    redirect_to events_path, alert: "ไม่พบอีเว้นท์"
  end

  def status
    result = Events::ChangeStatus.call(actor: current_admin, id: params[:id],
                                       to: params[:to].to_s, repo: repo, audit: audit)
    if result.success?
      redirect_to event_path(params[:id]), notice: "เปลี่ยนสถานะแล้ว"
    else
      redirect_to event_path(params[:id]), alert: result.error
    end
  rescue Ports::NotFound
    redirect_to events_path, alert: "ไม่พบอีเว้นท์"
  end

  private
    def load_event
      @event = repo.find(params[:id])
    rescue Ports::NotFound
      redirect_to events_path, alert: "ไม่พบอีเว้นท์"
    end

    def update_params = params.require(:event).permit(:name_thai, :name_eng, :area_name, :province)
    def repo = Persistence::ArEventRepository.new
    def audit = Persistence::ArAuditRecorder.new
end
