package models

import (
	"time"

	"gorm.io/gorm"
)

// Invite model
type Invite struct {
	gorm.Model
	Email        string
	Token        string
	InviterID    uint
	InviteeID    uint
	AcceptedAt   time.Time
	OrganizationID uint
}
