package jobs

import (
	"fmt"
	"log"
	"sway-go/models" // Assuming model types and data access functions are in this package.
)

// OnUserVoteUpdateScoresJob replicates the functionality of the Ruby job that is triggered
// when a user casts a vote. It calls a service (which we will replicate here) to update
// the relevant scores.
func OnUserVoteUpdateScoresJob(userVote *models.UserVote) {
	log.Printf("OnUserVoteUpdateScoresJob.perform - UserVote = %d", userVote.ID)

	// The Ruby job calls `ScoreUpdaterService.new(user_vote).run`.
	// We will implement the logic of that service here.
	if err := runScoreUpdater(userVote); err != nil {
		log.Printf("ERROR running score updater for UserVote %d: %v", userVote.ID, err)
		// Consider Sentry capture here.
	}
}

// runScoreUpdater contains the core logic inferred from the `ScoreUpdaterService` in Ruby.
// It updates the UserLegislatorScore for the user and their legislators, and also
// updates the aggregate LegislatorDistrictScore.
func runScoreUpdater(userVote *models.UserVote) error {
	user, err := models.GetUserByID(userVote.UserID)
	if err != nil {
		return fmt.Errorf("could not find user %d: %w", userVote.UserID, err)
	}

	legislators, err := models.GetLegislatorsForUser(user.ID)
	if err != nil {
		return fmt.Errorf("could not get legislators for user %d: %w", user.ID, err)
	}

	for _, legislator := range legislators {
		// 1. Update the individual UserLegislatorScore
		uls, err := models.FindOrCreateUserLegislatorScore(user.ID, legislator.ID)
		if err != nil {
			log.Printf("Failed to find or create UserLegislatorScore for user %d, legislator %d: %v", user.ID, legislator.ID, err)
			continue // Move to the next legislator
		}

		// 2. Update the aggregate LegislatorDistrictScore
		lds, err := models.FindOrCreateLegislatorDistrictScore(legislator.ID)
		if err != nil {
			log.Printf("Failed to find or create LegislatorDistrictScore for legislator %d: %v", legislator.ID, err)
			continue // Move to the next legislator
		}

		// Get the legislator's vote on the same bill to compare
		legislatorVote, err := models.GetLegislatorVote(legislator.ID, userVote.BillID)
		if err != nil {
			// This could mean the legislator hasn't voted yet, which is a valid state.
			log.Printf("Could not find legislator vote for legislator %d on bill %d: %v", legislator.ID, userVote.BillID, err)
		}

		// Update both scores based on the comparison
		updateScoresBasedOnVote(uls, lds, userVote, legislatorVote)

		// Save the updated scores
		if err := models.UpdateUserLegislatorScore(uls); err != nil {
			log.Printf("Failed to save updated UserLegislatorScore %d: %v", uls.ID, err)
		}
		if err := models.UpdateLegislatorDistrictScore(lds); err != nil {
			log.Printf("Failed to save updated LegislatorDistrictScore %d: %v", lds.ID, err)
		}
	}

	return nil
}

// updateScoresBasedOnVote increments the counters on the score records.
// This is an incremental update for a single new user vote.
func updateScoresBasedOnVote(uls *models.UserLegislatorScore, lds *models.LegislatorDistrictScore, userVote *models.UserVote, legislatorVote *models.LegislatorVote) {
	if legislatorVote == nil {
		// Legislator has not voted on this bill yet.
		uls.CountNoLegislatorVote++
		lds.CountNoLegislatorVote++
		return
	}

	if legislatorVote.Support == "ABSTAIN" {
		uls.CountLegislatorAbstained++
		lds.CountLegislatorAbstained++
	} else if legislatorVote.Support == userVote.Support {
		uls.CountAgreed++
		lds.CountAgreed++
	} else {
		uls.CountDisagreed++
		lds.CountDisagreed++
	}
}
