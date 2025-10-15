package models

import "gorm.io/gorm"

// BillScoreDistrict model
type BillScoreDistrict struct {
	gorm.Model
	BillScoreID uint
	DistrictID  uint
}
