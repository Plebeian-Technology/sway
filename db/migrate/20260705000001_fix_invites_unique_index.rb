# frozen_string_literal: true

# WS2.2: 20240510201541_create_invites.rb had a typo —
#   add_index :invites, [:inviter_id, :inviter_id], unique: true
# — which built a UNIQUE index on inviter_id ALONE (named, revealingly,
# index_invites_on_inviter_id_and_inviter_id). It caps every inviter at a
# single Invite row, so the second invitee to register through an inviter's
# link raised ActiveRecord::RecordNotUnique in create_invite and rolled back
# their whole registration.
class FixInvitesUniqueIndex < ActiveRecord::Migration[8.1]
  def up
    remove_index :invites, name: "index_invites_on_inviter_id_and_inviter_id"
    # The plain non-unique index on inviter_id is a redundant prefix of the new
    # composite (inviter_id, invitee_id); the composite serves inviter_id-only
    # lookups (InfluenceService's Invite.where(inviter_id:).count) equally well.
    remove_index :invites, name: "index_invites_on_inviter_id"

    # No dedup needed: the botched unique-on-inviter_id index guaranteed at most
    # one row per inviter, so no (inviter_id, invitee_id) pair can already collide.
    add_index :invites, [:inviter_id, :invitee_id], unique: true
  end

  def down
    remove_index :invites, name: "index_invites_on_inviter_id_and_invitee_id"
    add_index :invites, :inviter_id
    add_index :invites, [:inviter_id, :inviter_id], unique: true
  end
end
