module Events
  class ChangeStatus
    # allowed[new_status] = statuses an event may move FROM.
    # Mirrors the Go backend's ValidateStatus map (internal/model/event.go:444)
    # exactly, EXCEPT two targets are intentionally absent:
    # - "pending_email_confirm": in Go, entering this status normally happens
    #   via EscalateEventStatus (verification email + quota deduction) which
    #   this app cannot replicate; the PATCH-only backward correction
    #   email_confirmed→pending_email_confirm is conservatively omitted too.
    # - "quotation": not a row in the event_statuses catalog; Go-internal.
    # NOTE: Go's table is mostly BACKWARD corrections (the forward flow lives
    # in EscalateEventStatus) — that suits an admin correction tool exactly.
    # Admin changes are silent: no emails, no quota changes — every change
    # lands in the audit log instead.
    TRANSITIONS = {
      "draft"            => ["draft", "pending_email_confirm", ""].freeze,
      "email_confirmed"  => ["survey_published"].freeze,
      "quotation_review" => ["quotation"].freeze,
      "survey_published" => ["collecting"].freeze,
      "collecting"       => ["quotation_review", "reject"].freeze,
      "in_progress"      => ["collecting"].freeze,
      "done"             => ["in_progress"].freeze,
      "complete"         => ["done", "collecting"].freeze,
      "carbon_credit"    => ["complete"].freeze,
      "offset_carbon"    => ["complete", "carbon_credit"].freeze,
      "send_data"        => ["complete", "offset_carbon"].freeze,
      "reject"           => ["in_progress"].freeze
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
