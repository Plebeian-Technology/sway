package jobs

import (
	"log"
	"sway-go/models"
	// "sway/services" // Assuming an email sending service package exists.
)

// OnUserEmailSavedSendEmailToLegislatorJob replicates the functionality of the
// corresponding Ruby job. It checks if an email is ready to be sent, updates its
// status, and then dispatches it.
func OnUserEmailSavedSendEmailToLegislatorJob(userLegislatorEmail *models.UserLegislatorEmail) {
	// In the Ruby version, `sendable?` is a method on the model. We'll assume a similar
	// method or logic exists on our Go model. For this implementation, we'll just check a status field.
	if userLegislatorEmail.Status != "queued" {
		log.Printf("Email %d is not in a 'queued' state, skipping. Status: %s", userLegislatorEmail.ID, userLegislatorEmail.Status)
		return
	}

	// Update status to "sending" before attempting to send.
	userLegislatorEmail.Status = "sending"
	if err := models.UpdateUserLegislatorEmail(userLegislatorEmail); err != nil {
		log.Printf("Failed to update email status to 'sending' for ID %d: %v", userLegislatorEmail.ID, err)
		// If we can't even update the status, we shouldn't proceed.
		return
	}

	// This is where the actual email sending logic would go.
	// This would likely be in a separate `services` package that handles SMTP
	// or an external email API (like SendGrid, Mailgun, etc.).
	// e.g., err := services.Email.Send(userLegislatorEmail.ConstructEmail())
	err := sendEmail(userLegislatorEmail) // Placeholder for the actual send logic.

	if err != nil {
		log.Printf("Failed to send email for ID %d: %v", userLegislatorEmail.ID, err)
		// If sending fails, update the status to "failed".
		userLegislatorEmail.Status = "failed"
		if updateErr := models.UpdateUserLegislatorEmail(userLegislatorEmail); updateErr != nil {
			log.Printf("Additionally failed to update email status to 'failed' for ID %d: %v", userLegislatorEmail.ID, updateErr)
		}
		// In a real app, you'd report this to an error service like Sentry.
		return
	}

	// If sending was successful, update the status to "sent".
	userLegislatorEmail.Status = "sent"
	if err := models.UpdateUserLegislatorEmail(userLegislatorEmail); err != nil {
		log.Printf("Failed to update email status to 'sent' for ID %d: %v", userLegislatorEmail.ID, err)
	}

	log.Printf("Successfully sent email for UserLegislatorEmail ID %d.", userLegislatorEmail.ID)
}

// sendEmail is a placeholder for the actual email dispatch logic.
func sendEmail(email *models.UserLegislatorEmail) error {
	// Here you would connect to an SMTP server or use an API client.
	log.Printf("Simulating sending email to legislator: %s", email.ToAddress)
	log.Printf("Subject: %s", email.Subject)
	log.Printf("Body: %s", email.Body)
	// To simulate a potential failure, you could add:
	// return errors.New("SMTP server not available")
	return nil
}
