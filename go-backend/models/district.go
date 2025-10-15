package models

import "gorm.io/gorm"

// District model
type District struct {
	gorm.Model
	Name      string
	State     string
	Chamber   string
	Number    string
	SwayLocaleID uint
}
