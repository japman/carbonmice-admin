module AdminAuth
  # Single authority for role-based permissions across the app.
  # Visibility changes (e.g. letting other roles see the audit log later)
  # are made HERE and nowhere else.
  class AccessPolicy
    PERMISSIONS = {
      "viewer"     => %i[view_operations],
      "admin"      => %i[view_operations manage_events manage_app_users manage_master_data],
      "superadmin" => %i[view_operations manage_events manage_app_users manage_master_data
                         manage_admin_users view_audit_log]
    }.freeze

    ACTIONS = PERMISSIONS.values.flatten.uniq.freeze

    def self.allows?(role:, action:)
      PERMISSIONS.fetch(role.to_s, []).include?(action&.to_sym)
    end
  end
end
