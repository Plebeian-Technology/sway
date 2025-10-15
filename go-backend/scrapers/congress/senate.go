package congress

import (
	"fmt"
	"sway-go/scrapers"
)

const senateBaseURL = "https://www.senate.gov"

// SenateVote represents a single legislator's vote in the Senate.
// Note the structure is different from the House XML.
type SenateVote struct {
	FirstName  string `xml:"first_name"`
	LastName   string `xml:"last_name"`
	StateCode  string `xml:"state"`
	Party      string `xml:"party"`
	VoteCast   string `xml:"vote_cast"` // Yea, Nay, Not Voting
}

// SenateVoteData is the top-level structure for the Senate vote XML.
type SenateVoteData struct {
	Members []SenateVote `xml:"members>member"`
}

// FetchSenateVotes fetches and parses roll call vote data from the Senate.
func FetchSenateVotes(congress, session, rollCallNumber int) ([]SenateVote, error) {
	client := scrapers.NewClient(senateBaseURL)
	client.WithHeader("Content-Type", "text/xml")

	// Format the roll call number (e.g., 421 -> "00421")
	voteNumber := fmt.Sprintf("%05d", rollCallNumber)

	path := fmt.Sprintf("/legislative/LIS/roll_call_votes/vote%d%d/vote_%d_%d_%s.xml",
		congress, session, congress, session, voteNumber)

	xmlData, err := client.Get(path)
	if err != nil {
		return nil, err
	}

	var voteData SenateVoteData
	if err := scrapers.ParseXML(xmlData, &voteData); err != nil {
		return nil, err
	}

	return voteData.Members, nil
}
