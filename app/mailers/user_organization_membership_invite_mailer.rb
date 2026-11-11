class UserOrganizationMembershipInviteMailer < ApplicationMailer
  def invite(invite)
    @invite = invite
    @organization = invite.organization
    @inviter = invite.inviter
    # @lat: [[outbound-email#Why mailers default to outreach@sway.vote and bake invite expiry into signed tokens]]
    @signed_token = invite.signed_id(
      purpose: :accept_invite,
      expires_at: invite.expires_at
    )

    mail(
      to: @invite.invitee_email,
      subject:
        "#{@inviter.full_name} invited you to join #{@organization.name} on Sway"
    )
  end
end
