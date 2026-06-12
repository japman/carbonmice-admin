require_relative "../../domain_helper"

class AccessPolicyTest < Minitest::Test
  def test_viewer_can_view_operations_but_not_manage_or_audit
    assert AdminAuth::AccessPolicy.allows?(role: "viewer", action: :view_operations)
    refute AdminAuth::AccessPolicy.allows?(role: "viewer", action: :manage_events)
    refute AdminAuth::AccessPolicy.allows?(role: "viewer", action: :view_audit_log)
  end

  def test_admin_manages_operations_but_not_admin_accounts_or_audit
    assert AdminAuth::AccessPolicy.allows?(role: "admin", action: :manage_events)
    assert AdminAuth::AccessPolicy.allows?(role: "admin", action: :manage_app_users)
    assert AdminAuth::AccessPolicy.allows?(role: "admin", action: :manage_master_data)
    refute AdminAuth::AccessPolicy.allows?(role: "admin", action: :manage_admin_users)
    refute AdminAuth::AccessPolicy.allows?(role: "admin", action: :view_audit_log)
  end

  def test_superadmin_can_do_everything
    AdminAuth::AccessPolicy::ACTIONS.each do |action|
      assert AdminAuth::AccessPolicy.allows?(role: "superadmin", action: action),
             "superadmin should be allowed #{action}"
    end
  end

  def test_unknown_role_or_action_is_denied
    refute AdminAuth::AccessPolicy.allows?(role: "hacker", action: :view_operations)
    refute AdminAuth::AccessPolicy.allows?(role: "admin", action: :launch_rockets)
    refute AdminAuth::AccessPolicy.allows?(role: nil, action: :view_operations)
    refute AdminAuth::AccessPolicy.allows?(role: "admin", action: nil)
  end

  def test_string_action_is_coerced
    assert AdminAuth::AccessPolicy.allows?(role: "viewer", action: "view_operations"),
           "string action should be coerced to symbol"
  end
end
