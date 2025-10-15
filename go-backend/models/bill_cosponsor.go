package models

import "gorm.io/gorm"

// BillCosponsor model
type BillCosponsor struct {
	gorm.Model
	BillID       uint
	LegislatorID uint
}
