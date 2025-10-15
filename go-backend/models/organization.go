package models

import "gorm.io/gorm"

// Organization model
type Organization struct {
	gorm.Model
	Name string
}
