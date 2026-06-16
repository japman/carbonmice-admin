module Events
  class DeleteDraft
    # Permanent CASCADE delete — the deliberate exception to the app's
    # soft-delete-everything rule. Only a "draft" event may be removed; the
    # adapter cascade-deletes the event's whole FK subtree (carbon emissions,
    # documents, schedules, …) in one transaction. public.events is Go-owned, so
    # this is scoped strictly to this event's descendants and nothing else.
    def self.call(actor:, id:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการอีเว้นท์") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_events)

      event = repo.find(id)
      status = event.event_status.to_s
      return Result.failure("ลบถาวรได้เฉพาะอีเว้นท์สถานะ draft เท่านั้น") unless status == "draft"

      name_thai = event.name_thai.to_s
      label = name_thai.empty? ? event.name_eng : name_thai
      record = repo.hard_delete_cascade(id)
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
