# Stamped into Go-owned updated_by columns so the Go side's history shows
# exactly which admin changed a row from this app.
module AuditIdentity
  def self.for(actor) = "carbonmice-admin:#{actor.email_address}"
end
