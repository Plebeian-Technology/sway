package models

import (
	"time"

	"gorm.io/gorm"
)

// Vote model
type Vote struct {
	gorm.Model
	BillID uint
	Date   time.Time
	Chamber string
	Motion string
}
