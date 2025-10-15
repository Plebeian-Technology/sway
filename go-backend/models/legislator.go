package models

import "gorm.io/gorm"

// Legislator model
type Legislator struct {
	gorm.Model
	FullName  string
	Party     string
	DistrictID uint
}
