module Events
  class DeleteDraft
    # Permanent (hard) delete — the deliberate exception to the app's
    # soft-delete-everything rule. Only a "draft" event may be removed, and only
    # when nothing references it: public.events is Go-owned and ~24 tables point
    # at it via FK RESTRICT, so the adapter surfaces any reference as a failure
    # (we never orphan child rows or cascade-delete Go data).
    def self.call(actor:, id:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการอีเว้นท์") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_events)

      event = repo.find(id)
      status = event.event_status.to_s
      return Result.failure("ลบถาวรได้เฉพาะอีเว้นท์สถานะ draft เท่านั้น") unless status == "draft"

      name_thai = event.name_thai.to_s
      label = name_thai.empty? ? event.name_eng : name_thai
      record = repo.hard_delete(id)
      audit.record(action: "events.deleted", actor: actor, target: record,
                   changes: { "name" => label, "event_status" => status })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบอีเว้นท์")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
