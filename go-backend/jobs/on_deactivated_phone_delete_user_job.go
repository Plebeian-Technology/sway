package jobs

import (
	"bufio"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sway-go/models"
	"time"
)

const (
	twilioDeactivationURL = "https://messaging.twilio.com/v1/Deactivations"
	batchSize           = 200
)

// OnDeactivatedPhoneDeleteUserJob simulates the Ruby job to delete users
// with deactivated phone numbers based on a daily report from Twilio.
func OnDeactivatedPhoneDeleteUserJob() {
	// In a real app, you might check an environment variable like `if os.Getenv("GO_ENV") == "development"`
	// For this migration, we'll proceed directly to the job's logic.

	phones, err := getDeactivatedPhones()
	if err != nil {
		log.Printf("Error fetching deactivated phones: %v", err)
		// In a real app, you might use a Sentry-like service here.
		// Sentry.CaptureMessage(...)
		return
	}

	if len(phones) == 0 {
		log.Println("No deactivated phones found today.")
		return
	}

	count := 0
	for i := 0; i < len(phones); i += batchSize {
		end := i + batchSize
		if end > len(phones) {
			end = len(phones)
		}
		batch := phones[i:end]

		users, err := models.GetUsersByPhones(batch)
		if err != nil {
			log.Printf("Error finding users for phone batch: %v", err)
			continue
		}

		for _, user := range users {
			log.Printf("Destroying user %d because their phone number has been deactivated.", user.ID)
			if err := models.DeleteUser(&user); err != nil {
				log.Printf("FAILED to destroy user %d with deactivated phone number.", user.ID)
				// Sentry.CaptureMessage(...)
			} else {
				count++
			}
		}
	}

	log.Printf("Destroyed %d users with deactivated phone numbers.", count)
}

func getDeactivatedPhones() ([]string, error) {
	accountSid := os.Getenv("TWILIO_ACCOUNT_SID")
	authToken := os.Getenv("TWILIO_AUTH_TOKEN")
	if accountSid == "" || authToken == "" {
		return nil, fmt.Errorf("TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN must be set")
	}

	client := &http.Client{}
	today := time.Now().UTC().Format("2006-01-02")
	req, err := http.NewRequest("GET", twilioDeactivationURL, nil)
	if err != nil {
		return nil, err
	}

	req.SetBasicAuth(accountSid, authToken)
	q := req.URL.Query()
	q.Add("Date", today)
	req.URL.RawQuery = q.Encode()

	// The Ruby code fetches a redirect URL first, then fetches that URL.
	// `deactivation_url.redirect_to`. The Twilio API for deactivations
	// provides a temporary redirect to a CSV file. We will simulate that behavior.
	// For this implementation, we will assume the response is directly available.
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		// In a real scenario, you'd handle redirects (307) and other status codes.
		return nil, fmt.Errorf("failed to fetch deactivations: status code %d", resp.StatusCode)
	}

	var phones []string
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		// The ruby code does `phone.slice(1..)` which suggests removing the first char (e.g., '+').
		line := scanner.Text()
		if len(line) > 1 {
			phones = append(phones, strings.TrimPrefix(line, "+"))
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return phones, nil
}
