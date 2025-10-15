package models

import (
	"gorm.io/gorm"
)

// Invite model
type Invite struct {
	gorm.Model
	InviterID    uint
	Inviter      User `gorm:"foreignKey:InviterID"`
	InviteeID    uint
	Invitee      User `gorm:"foreignKey:InviteeID"`
}
