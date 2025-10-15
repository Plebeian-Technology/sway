package models

import "gorm.io/gorm"

// UserOrganizationMembership model
type UserOrganizationMembership struct {
	gorm.Model
	UserID         uint
	OrganizationID uint
	Role           string
}
