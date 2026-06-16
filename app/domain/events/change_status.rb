module Events
  class ChangeStatus
    # Admin override: move the event to ANY status that exists in the
    # event_statuses catalog (the dropdown is the catalog). This is a manual
    # correction tool — the change is a direct DB write: no emails, no quota
    # deductions (those only happen inside the Go backend's own escalation flow),
    # and every change is recorded in the audit log. The single guard is that the
    # target must be a real catalog status, so we never write a garbage value.
    def self.call(actor:, id:, to:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการอีเว้นท์") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_events)

      to = to.to_s
      return Result.failure("สถานะปลายทางไม่ถูกต้อง") unless repo.known_status?(to)

      event = repo.find(id)
      from = event.event_status.to_s
      record = repo.update_status(id, to: to, updated_by: AuditIdentity.for(actor))
      audit.record(action: "events.status_changed", actor: actor, target: record,
                   changes: { "event_status" => { "from" => from, "to" => to } })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบอีเว้นท์")
    end
  end
end
