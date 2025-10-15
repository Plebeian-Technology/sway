package mailers

import (
	"fmt"
	"log"

	"github.com/sendgrid/sendgrid-go/helpers/mail"
)

// SendOrganizationInviteEmail constructs and sends an email to invite a user to an organization.
func SendOrganizationInviteEmail(invite *UserOrganizationMembershipInvite) error {
	// Assume the 'invite' model contains the necessary nested structs or fields.
	organization := invite.Organization
	inviter := invite.Inviter

	// 1. Construct the subject
	subject := fmt.Sprintf("%s invited you to join %s on Sway", inviter.FullName, organization.Name)

	// 2. Construct the email body
	// The original Rails mailer would have a view template. We will create a simple body here.
	plainTextContent := fmt.Sprintf("Hello,\n\nYou have been invited by %s to join the organization '%s' on Sway.\n\nThanks,\nThe Sway Team", inviter.FullName, organization.Name)
	htmlContent := fmt.Sprintf("Hello,<br><br>You have been invited by %s to join the organization '<strong>%s</strong>' on Sway.<br><br>Thanks,<br>The Sway Team", inviter.FullName, organization.Name)

	// 3. Set up the sender and recipient
	from := mail.NewEmail("Sway Team", "no-reply@sway.vote")
	to := mail.NewEmail("", invite.InviteeEmail) // Recipient name is often blank for invites

	// 4. Send the email using the base mailer
	err := SendEmail(from, to, subject, plainTextContent, htmlContent)
	if err != nil {
		log.Printf("Error sending organization invite to %s: %v", invite.InviteeEmail, err)
		return err
	}

	log.Printf("Successfully sent organization invite email to %s", invite.InviteeEmail)
	return nil
}
