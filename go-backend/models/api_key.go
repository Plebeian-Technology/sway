package models

import (
	"time"

	"gorm.io/gorm"
)

// APIKey model
type APIKey struct {
	gorm.Model
	BearerType    string `gorm:"not null"`
	LastUsedOnUTC time.Time
	Name          string
	TokenDigest   string `gorm:"not null;unique"`
	BearerID      uint   `gorm:"not null"`
}
