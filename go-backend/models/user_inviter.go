package models

import "gorm.io/gorm"

// UserInviter model
type UserInviter struct {
	gorm.Model
	UserID     uint
	InviterID  uint
	InviteUUID string
}
