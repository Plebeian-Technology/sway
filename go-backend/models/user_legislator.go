package models

import "gorm.io/gorm"

// UserLegislator model
type UserLegislator struct {
	gorm.Model
	UserID       uint
	LegislatorID uint
}
