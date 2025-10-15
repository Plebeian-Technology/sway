package models

import "gorm.io/gorm"

// OrganizationBillPosition model
type OrganizationBillPosition struct {
	gorm.Model
	OrganizationID uint
	BillID         uint
	Position       string
}
