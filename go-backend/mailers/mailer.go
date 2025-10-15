package mailers

import (
	"fmt"
	"os"

	"github.com/sendgrid/sendgrid-go"
	"github.com/sendgrid/sendgrid-go/helpers/mail"
)

// SendEmail sends an email using the SendGrid client.
// It abstracts the basic setup for sending a transactional email.
func SendEmail(from *mail.Email, to *mail.Email, subject string, plainTextContent string, htmlContent string) error {
	apiKey := os.Getenv("SENDGRID_API_KEY")
	if apiKey == "" {
		return fmt.Errorf("SENDGRID_API_KEY environment variable not set")
	}

	client := sendgrid.NewSendClient(apiKey)

	message := mail.NewSingleEmail(from, subject, to, plainTextContent, htmlContent)

	response, err := client.Send(message)
	if err != nil {
		return err
	}

	// 2xx status codes indicate success
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("failed to send email: SendGrid returned status %d with body: %s", response.StatusCode, response.Body)
	}

	return nil
}
