# frozen_string_literal: true

class RenameUserInvitersToUserInviteLinks < ActiveRecord::Migration[8.1]
  def up
    rename_table :user_inviters, :user_invite_links
    execute("UPDATE shortened_urls SET owner_type = 'UserInviteLink' WHERE owner_type = 'UserInviter'")
  end

  def down
    execute("UPDATE shortened_urls SET owner_type = 'UserInviter' WHERE owner_type = 'UserInviteLink'")
    rename_table :user_invite_links, :user_inviters
  end
end
