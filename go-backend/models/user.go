package models

import (
	"time"

	"gorm.io/gorm"
)

// User model
type User struct {
	gorm.Model
	CurrentSignInAt      time.Time
	CurrentSignInIP      string
	Email                *string `gorm:"unique"`
	FullName             string
	IsAdmin              bool `gorm:"default:false"`
	IsEmailVerified      bool
	IsPhoneVerified      bool
	IsRegisteredToVote   bool
	IsRegistrationComplete bool
	LastSignInAt         time.Time
	LastSignInIP         string
	Phone                string `gorm:"unique"`
	SignInCount          int    `gorm:"default:0;not null"`
	WebauthnID           string `gorm:"unique"`
}
