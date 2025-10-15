package mailers

import (
	"fmt"
	"log"
	"os"
	"strings"
	"sway-go/models" // Assuming models are in this package

	"github.com/sendgrid/sendgrid-go/helpers/mail"
)

// SendEmailToLegislator constructs and sends an email from a user to a legislator.
// It replicates the logic from the UserLegislatorEmailMailer in the Rails app.
func SendEmailToLegislator(emailData *models.UserLegislatorEmail) error {
	// Assumed models are passed in emailData. We extract them for easier access.
	user := emailData.User
	legislator := emailData.Legislator
	bill := emailData.Bill

	// Build the dynamic parts of the email.
	intro := buildIntro(user, legislator, emailData)
	body := buildBody(emailData)
	conclusion := fmt.Sprintf("Thank you,\n%s", user.FullName)

	plainTextContent := fmt.Sprintf("%s\n\n%s\n\n%s", intro, body, conclusion)
	// For simplicity, we'll use the same content for HTML. A real implementation might use HTML templates.
	htmlContent := strings.ReplaceAll(plainTextContent, "\n", "<br>")

	// Configure sender, recipient, and other email fields.
	from := mail.NewEmail("Sway Team", "outreach@sway.vote")
	toAddress := getToAddress(legislator)
	to := mail.NewEmail(legislator.FullName, toAddress)
	subject := buildSubject(emailData)

	// The SendEmail function will handle sending.
	err := SendEmail(from, to, subject, plainTextContent, htmlContent)
	if err != nil {
		log.Printf("Error sending email to legislator %s for user %s: %v", legislator.FullName, user.FullName, err)
		return err
	}

	log.Printf("Successfully sent email to legislator %s on behalf of user %s", legislator.FullName, user.FullName)
	return nil
}

func buildIntro(user *models.User, legislator *models.Legislator, emailData *models.UserLegislatorEmail) string {
	registeredVoterText := "I"
	if user.IsRegisteredToVote {
		registeredVoterText = "I am registered to vote and"
	}

	residenceText := "in your district"
	if legislator.AtLarge {
		residenceText = fmt.Sprintf("in %s", strings.ToTitle(emailData.SwayLocale.City))
	}

	addressText := ""
	if user.Address != nil && user.Address.FullAddress != "" {
		addressText = fmt.Sprintf(" at %s", user.Address.FullAddress)
	}

	return fmt.Sprintf("Hello %s %s,\n\nMy name is %s and %s reside %s%s.",
		legislator.Title, legislator.LastName, user.FullName, registeredVoterText, residenceText, addressText)
}

func buildBody(emailData *models.UserLegislatorEmail) string {
	bill := emailData.Bill
	billLinkText := fmt.Sprintf("which can be found here - %s", bill.Link)

	if emailData.UserVote != nil {
		supportText := "oppose"
		if emailData.UserVote.Support == "FOR" {
			supportText = "support"
		}
		return fmt.Sprintf("Please %s bill %s: %s, %s",
			supportText, bill.ExternalID, bill.Title, billLinkText)
	}

	return fmt.Sprintf("I am writing to you today because I would like to know your position on bill %s: %s, %s",
		bill.ExternalID, bill.Title, billLinkText)
}

func buildSubject(emailData *models.UserLegislatorEmail) string {
	uv := emailData.UserVote
	bill := emailData.Bill

	if uv != nil {
		support := "Oppose"
		if uv.Support == "FOR" {
			support = "Support"
		}
		return fmt.Sprintf("%s Bill %s", support, bill.ExternalID)
	}

	return fmt.Sprintf("Bill %s", bill.ExternalID)
}

func getToAddress(legislator *models.Legislator) string {
	if os.Getenv("GO_ENV") == "production" {
		return legislator.Email
	}

	// For non-production, munge the email address to prevent sending real emails.
	if legislator.Email == "" {
		return ""
	}
	parts := strings.Split(legislator.Email, "@")
	return fmt.Sprintf("%s@sway.vote", parts[0])
}
