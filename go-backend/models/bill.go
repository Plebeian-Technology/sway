package models

import "gorm.io/gorm"

// Bill model
type Bill struct {
	gorm.Model
	Title       string
	Description string
	Session     string
	BillNumber  string
	Status      string
}
