package models

import "gorm.io/gorm"

// RefreshToken model
type RefreshToken struct {
	gorm.Model
	UserID uint
	Token  string
}
