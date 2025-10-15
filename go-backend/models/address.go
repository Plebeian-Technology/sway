package models

import "gorm.io/gorm"

// Address model
type Address struct {
	gorm.Model
	AddressableID   uint
	AddressableType string
	City            string
	Country         string
	Line1           string
	Line2           string
	PostalCode      string
	State           string
}
