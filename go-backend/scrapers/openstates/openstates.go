package openstates

import (
	"fmt"
	"os"
	"sway-go/scrapers"
)

const openStatesBaseURL = "https://v3.openstates.org"

// Vote represents a single legislator's vote from the Open States API.
type Vote struct {
	Option    string `json:"option"` // "yes", "no", etc.
	VoterID   string `json:"voter_id"`
	VoterName string `json:"voter_name"`
}

// VoteResponse is the structure of the JSON response from the Open States API.
type VoteResponse struct {
	Votes []Vote `json:"votes"`
}

// FetchVotes fetches legislator votes for a given bill from the Open States API.
// The logic is the same for both House and Senate, so one function suffices.
func FetchVotes(regionCode string, billCreatedAtYear int, externalBillID string) ([]Vote, error) {
	apiKey := os.Getenv("OPEN_STATES_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("OPEN_STATES_API_KEY environment variable not set")
	}

	client := scrapers.NewClient(openStatesBaseURL)
	client.WithHeader("X-API-KEY", apiKey)

	path := fmt.Sprintf("/bills/%s/%d/%s", regionCode, billCreatedAtYear, externalBillID)

	jsonData, err := client.Get(path)
	if err != nil {
		return nil, err
	}

	var voteResponse VoteResponse
	if err := scrapers.ParseJSON(jsonData, &voteResponse); err != nil {
		return nil, err
	}

	return voteResponse.Votes, nil
}
