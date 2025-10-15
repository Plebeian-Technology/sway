package models

import "gorm.io/gorm"

// LegislatorVote model
type LegislatorVote struct {
	gorm.Model
	LegislatorID uint
	VoteID       uint
	Vote         string
}
