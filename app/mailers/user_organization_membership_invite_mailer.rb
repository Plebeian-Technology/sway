class UserOrganizationMembershipInviteMailer < ApplicationMailer
    def invite(invite)
        @invite = invite
        @organization = invite.organization
        @inviter = invite.inviter

        mail(to: @invite.invitee_email, 
subject: "#{@inviter.full_name} invited you to join #{@organization.name} on Sway")
    end
end
