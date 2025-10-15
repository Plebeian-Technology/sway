package models

import (
	"time"

	"gorm.io/gorm"
)

// OrganizationBillPositionChange model
type OrganizationBillPositionChange struct {
	gorm.Model
	OrganizationBillPositionID uint
	OldPosition                string
	NewPosition                string
	ChangedAt                  time.Time
}
