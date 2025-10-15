package models

import "gorm.io/gorm"

// BillScore model
type BillScore struct {
	gorm.Model
	BillID uint
	Score  int
}
