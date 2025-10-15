package models

import (
	"time"

	"gorm.io/gorm"
)

// BillNotification model
type BillNotification struct {
	gorm.Model
	UserID uint
	BillID uint
	SentAt time.Time
}
