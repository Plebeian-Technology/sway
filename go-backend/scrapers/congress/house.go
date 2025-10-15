package congress

import (
	"fmt"
	"sway-go/scrapers"
	"time"
)

const houseBaseURL = "https://clerk.house.gov"

// HouseVote represents a single legislator's vote in the House.
type HouseVote struct {
	ExternalID string `xml:"legislator,attr,name-id"`
	Support    string `xml:"vote"`
}

// HouseVoteData is the top-level structure for the House vote XML.
type HouseVoteData struct {
	Votes []HouseVote `xml:"recorded-vote"`
}

// FetchHouseVotes fetches and parses roll call vote data from the House.
func FetchHouseVotes(rollCallNumber int) ([]HouseVote, error) {
	client := scrapers.NewClient(houseBaseURL)
	client.WithHeader("Content-Type", "text/xml")

	// Format the roll call number (e.g., 25 -> "025")
	roll := fmt.Sprintf("%03d", rollCallNumber)
	year := time.Now().Year()

	path := fmt.Sprintf("/evs/%d/roll%s.xml", year, roll)

	xmlData, err := client.Get(path)
	if err != nil {
		return nil, err
	}

	var voteData HouseVoteData
	if err := scrapers.ParseXML(xmlData, &voteData); err != nil {
		return nil, err
	}

	return voteData.Votes, nil
}
