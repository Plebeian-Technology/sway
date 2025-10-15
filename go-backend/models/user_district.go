package models

import "gorm.io/gorm"

// UserDistrict model
type UserDistrict struct {
	gorm.Model
	UserID     uint
	DistrictID uint
}
