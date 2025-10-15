package models

import "gorm.io/gorm"

// UserBill model
type UserBill struct {
	gorm.Model
	UserID uint
	BillID uint
}
