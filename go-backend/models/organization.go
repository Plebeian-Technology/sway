package models

import "gorm.io/gorm"

// Organization model
type Organization struct {
	gorm.Model
	IconPath     string
	Name         string `gorm:"not null;uniqueIndex:idx_organizations_on_name_and_sway_locale_id"`
	SwayLocaleID uint   `gorm:"not null;uniqueIndex:idx_organizations_on_name_and_sway_locale_id"`

	// Associations
	SwayLocale                SwayLocale
	UserOrganizationMemberships []UserOrganizationMembership `gorm:"foreignKey:OrganizationID"`
	OrganizationBillPositions   []OrganizationBillPosition   `gorm:"foreignKey:OrganizationID"`
}
