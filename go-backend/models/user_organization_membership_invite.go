package models

import (
	"time"

	"gorm.io/gorm"
)

// UserOrganizationMembershipInvite model
type UserOrganizationMembershipInvite struct {
	gorm.Model
	UserID         uint
	OrganizationID uint
	InviterID      uint
	AcceptedAt     time.Time
}
