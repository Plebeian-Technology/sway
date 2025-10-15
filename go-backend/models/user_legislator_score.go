package models

import "gorm.io/gorm"

// UserLegislatorScore model
type UserLegislatorScore struct {
	gorm.Model
	UserID       uint
	LegislatorID uint
	Score        int
}
