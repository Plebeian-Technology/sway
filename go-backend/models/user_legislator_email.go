package models

import (
	"time"

	"gorm.io/gorm"
)

// UserLegislatorEmail model
type UserLegislatorEmail struct {
	gorm.Model
	UserID       uint
	LegislatorID uint
	Email        string
	SentAt       time.Time
}
