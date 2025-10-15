package models

import "gorm.io/gorm"

// UserVote model
type UserVote struct {
	gorm.Model
	UserID uint
	VoteID uint
	Vote   string
}
