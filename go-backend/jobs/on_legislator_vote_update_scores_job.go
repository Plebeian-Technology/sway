package jobs

import (
	"log"
	"sway-go/models" // Assuming models for LegislatorVote, User, Bill, etc. exist.
)

// OnLegislatorVoteUpdateScoresJob replicates the business logic from the equivalent Ruby job.
// It is triggered when a legislator's vote changes, and it updates the aggregate
// LegislatorDistrictScore and the individual UserLegislatorScore for all relevant users.
func OnLegislatorVoteUpdateScoresJob(newlySavedLegislatorVote *models.LegislatorVote, previousSupport *string) {
	if newlySavedLegislatorVote.Support == *previousSupport {
		log.Printf("WARN: OnLegislatorVoteUpdateScoresJob triggered but vote support is unchanged. LegislatorVote ID: %d", newlySavedLegislatorVote.ID)
		return
	}

	legislator := newlySavedLegislatorVote.Legislator
	if legislator == nil {
		log.Printf("ERROR: Legislator not found for LegislatorVote ID: %d", newlySavedLegislatorVote.ID)
		return
	}

	// Get all users associated with this legislator.
	users, err := models.GetUsersForLegislator(legislator.ID)
	if err != nil {
		log.Printf("ERROR: Could not fetch users for legislator %d: %v", legislator.ID, err)
		return
	}

	if len(users) == 0 {
		log.Printf("No users found for legislator %d. Skipping score updates.", legislator.ID)
		return
	}

	// Update the aggregate district score.
	if err := updateLegislatorDistrictScore(newlySavedLegislatorVote, users); err != nil {
		log.Printf("ERROR: Failed to update LegislatorDistrictScore: %v", err)
		// Consider Sentry capture here.
	}

	// Update the individual user-legislator scores.
	if err := updateUserLegislatorScores(newlySavedLegislatorVote, users, previousSupport); err != nil {
		log.Printf("ERROR: Failed to update UserLegislatorScores: %v", err)
		// Consider Sentry capture here.
	}
}

// updateLegislatorDistrictScore recalculates the legislator's aggregate score based on all user votes in their district for a given bill.
func updateLegislatorDistrictScore(legislatorVote *models.LegislatorVote, users []models.User) error {
	score, err := models.FindOrCreateLegislatorDistrictScore(legislatorVote.LegislatorID)
	if err != nil {
		return err
	}

	userVotes, err := models.GetUserVotesForBill(legislatorVote.BillID, users)
	if err != nil {
		return err
	}

	// Recalculate counts from scratch based on the new vote.
	var agreed, disagreed, legislatorAbstained, noLegislatorVote int
	for _, uv := range userVotes {
		if legislatorVote.Support == "ABSTAIN" {
			legislatorAbstained++
		} else if legislatorVote.Support == uv.Support {
			agreed++
		} else { // This includes cases where legislator voted FOR/AGAINST and user voted otherwise.
			disagreed++
		}
	}
	// The 'no_legislator_vote' case from Ruby seems to imply a state before the legislator ever voted on the bill.
	// When a vote is *updated*, this count should logically be zero. We will assume this.
	noLegislatorVote = 0

	score.CountAgreed = agreed
	score.CountDisagreed = disagreed
	score.CountLegislatorAbstained = legislatorAbstained
	score.CountNoLegislatorVote = noLegislatorVote // Should be 0 after a vote is cast.

	return models.UpdateLegislatorDistrictScore(score)
}

// updateUserLegislatorScores performs an incremental update on each user's score with a legislator.
func updateUserLegislatorScores(legislatorVote *models.LegislatorVote, users []models.User, previousSupport *string) error {
	userLegislatorScores, err := models.GetUserLegislatorScores(legislatorVote.LegislatorID, users)
	if err != nil {
		return err
	}

	userVotes, err := models.GetUserVotesForBill(legislatorVote.BillID, users)
	if err != nil {
		return err
	}
	userVotesMap := make(map[uint]models.UserVote) // map by UserID for quick lookup
	for _, uv := range userVotes {
		userVotesMap[uv.UserID] = uv
	}

	for _, uls := range userLegislatorScores {
		userVote, ok := userVotesMap[uls.UserID]
		if !ok {
			continue // This user didn't vote on this bill, so no score change.
		}

		// Decrement counts based on the previous state
		if previousSupport == nil || *previousSupport == "" {
			uls.CountNoLegislatorVote--
		} else if *previousSupport == "ABSTAIN" {
			uls.CountLegislatorAbstained--
		} else if *previousSupport == userVote.Support {
			uls.CountAgreed--
		} else {
			uls.CountDisagreed--
		}

		// Increment counts based on the new state
		if legislatorVote.Support == "ABSTAIN" {
			uls.CountLegislatorAbstained++
		} else if legislatorVote.Support == userVote.Support {
			uls.CountAgreed++
		} else {
			uls.CountDisagreed++
		}

		// Ensure counts don't go below zero
		uls.CountAgreed = max(0, uls.CountAgreed)
		uls.CountDisagreed = max(0, uls.CountDisagreed)
		uls.CountLegislatorAbstained = max(0, uls.CountLegislatorAbstained)
		uls.CountNoLegislatorVote = max(0, uls.CountNoLegislatorVote)

		if err := models.UpdateUserLegislatorScore(uls); err != nil {
			log.Printf("Failed to update UserLegislatorScore for user %d and legislator %d: %v", uls.UserID, uls.LegislatorID, err)
			// Continue to the next score
		}
	}
	return nil
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
