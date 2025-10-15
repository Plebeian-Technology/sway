package models

import "gorm.io/gorm"

// SwayLocale model
type SwayLocale struct {
	gorm.Model
	Name string
}
