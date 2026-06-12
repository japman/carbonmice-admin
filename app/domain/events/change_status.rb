module Events
  class ChangeStatus
    # allowed[new_status] = statuses an event may move FROM.
    # Mirrors the Go backend's ValidateStatus (internal/model/event.go:444)
    # MINUS draft→pending_email_confirm, whose Go-side side effects
    # (verification email, quota deduction) this app cannot replicate.
    # Admin changes are silent corrections: no emails, no quota changes —
    # every change lands in the audit log instead.
    TRANSITIONS = {
      "draft"            => ["draft", "pending_email_confirm", ""],
      "email_confirmed"  => ["pending_email_confirm"],
      "quotation_review" => ["collecting"],
      "survey_published" => ["email_confirmed"],
      "collecting"       => ["survey_published"],
      "in_progress"      => ["collecting"],
      "done"             => ["in_progress"],
      "complete"         => ["done", "collecting"],
      "carbon_credit"    => ["complete"],
      "offset_carbon"    => ["complete", "carbon_credit"],
      "send_data"        => ["complete", "offset_carbon"],
      "reject"           => ["in_progress"]
    }.freeze

    def self.call(actor:, id:, to:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการอีเว้นท์") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_events)

      to = to.to_s
      allowed_from = TRANSITIONS[to]
      return Result.failure("สถานะปลายทางไม่ถูกต้อง") unless allowed_from

      event = repo.find(id)
      from = event.event_status.to_s
      unless allowed_from.include?(from)
        from_label = from.empty? ? "(ว่าง)" : from
        return Result.failure("เปลี่ยนสถานะจาก #{from_label} ไป #{to} ไม่ได้")
      end

      record = repo.update_status(id, to: to, updated_by: AuditIdentity.for(actor))
      audit.record(action: "events.status_changed", actor: actor, target: record,
                   changes: { "event_status" => { "from" => from, "to" => to } })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบอีเว้นท์")
    end
  end
end
