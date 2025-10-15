package maryland

import (
	"bytes"
	"fmt"
	"regexp"
	"strings"
	"sway-go/scrapers"

	"github.com/ledongthuc/pdf"
)

const marylandBaseURL = "https://mgaleg.maryland.gov"

// Vote represents a parsed vote from the Maryland PDF.
// Note: Unlike the Ruby version that maps names to external_ids via DB lookup,
// this version will return the raw names found in the PDF.
type Vote struct {
	LegislatorLastName string
	Support            string
}

// FetchMarylandVotes fetches and parses a PDF of vote records.
func FetchMarylandVotes(year int, chamber string, rollCallNumber int) ([]Vote, error) {
	client := scrapers.NewClient(marylandBaseURL)
	// The response is a PDF, so we don't set a typical Content-Type for the request.

	roll := fmt.Sprintf("%04d", rollCallNumber)
	path := fmt.Sprintf("/%dRS/votes/%s/%s.pdf", year, chamber, roll)

	pdfData, err := client.Get(path)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch PDF: %w", err)
	}

	// Placeholder for PDF parsing. In a real implementation, a library would be used
	text, err := readPDFText(pdfData)
	if err != nil {
		return nil, fmt.Errorf("failed to parse PDF text: %w", err)
	}

	return parseVoteText(text), nil
}

// readPDFText uses the pdf library to extract text from the raw PDF data.
func readPDFText(pdfData []byte) (string, error) {
	r, err := pdf.NewReader(bytes.NewReader(pdfData), int64(len(pdfData)))
	if err != nil {
		return "", err
	}

	var buf strings.Builder
	for i := 1; i <= r.NumPage(); i++ {
		p := r.Page(i)
		if p.V.IsNull() {
			continue
		}
		text, err := p.GetPlainText(nil)
		if err != nil {
			return "", err
		}
		buf.WriteString(text)
	}
	return buf.String(), nil
}

// parseVoteText processes the raw text extracted from the PDF to find votes.
// This logic is ported from the Ruby scraper.
func parseVoteText(text string) []Vote {
	var votes []Vote
	var currentSupport string

	// Regex to clean up lines and split names.
	re := regexp.MustCompile(`\s{2,}`)

	lines := strings.Split(text, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Check for section headers to determine the current vote type.
		lowerLine := strings.ToLower(line)
		if strings.Contains(lowerLine, "voting yea") {
			currentSupport = "FOR"
			continue
		} else if strings.Contains(lowerLine, "voting nay") {
			currentSupport = "AGAINST"
			continue
		} else if strings.Contains(lowerLine, "not voting") || strings.Contains(lowerLine, "excused") {
			currentSupport = "ABSTAIN"
			continue
		}

		// If we are in a voting section, parse the names.
		if currentSupport != "" {
			// Split the line by multiple spaces to separate names on the same line.
			names := re.Split(line, -1)
			for _, name := range names {
				name = strings.TrimSpace(name)
				if name != "" {
					// The Ruby code does complex matching against the DB. Here, we just record the name.
					votes = append(votes, Vote{LegislatorLastName: name, Support: currentSupport})
				}
			}
		}
	}

	return votes
}
