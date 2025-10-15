package models

import "gorm.io/gorm"

// BillSponsor model
type BillSponsor struct {
	gorm.Model
	BillID       uint
	LegislatorID uint
}
