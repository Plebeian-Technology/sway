package models

import "gorm.io/gorm"

// LegislatorDistrictScore model
type LegislatorDistrictScore struct {
	gorm.Model
	LegislatorID uint
	DistrictID   uint
	Score        int
}
