package models

import "gorm.io/gorm"

// UserAddress model
type UserAddress struct {
	gorm.Model
	UserID    uint
	AddressID uint
}
