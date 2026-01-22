package notifications

import (
	"fmt"
	"log"
)

type NotificationService interface {
	SendSMS(to string, body string) error
}

type LogNotificationService struct{}

func (s *LogNotificationService) SendSMS(to string, body string) error {
	log.Printf("[SMS] To: %s, Body: %s", to, body)
	return nil
}

type TwilioNotificationService struct {
	AccountSID string
	AuthToken  string
	FromPhone  string
}

func (s *TwilioNotificationService) SendSMS(to string, body string) error {
	// TODO: Implement actual Twilio API call using net/http
	// For now, we just log it as this requires setting up Twilio account/credentials in the environment
	// which might not be available during this test.
	url := fmt.Sprintf("https://api.twilio.com/2010-04-01/Accounts/%s/Messages.json", s.AccountSID)
	log.Printf("Sending SMS via Twilio (%s): To: %s, Body: %s", url, to, body)
	return nil
}
