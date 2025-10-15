package models

import (
	"strings"

	"golang.org/x/text/cases"
	"golang.org/x/text/language"
	"gorm.io/gorm"
)

// Address model
type Address struct {
	gorm.Model
	City       string  `gorm:"not null"`
	Country    string  `gorm:"not null;default:'US'"`
	Latitude   float64
	Longitude  float64
	PostalCode string  `gorm:"not null"`
	RegionCode string  `gorm:"not null"`
	Street     string  `gorm:"not null"`
	Street2    string
	Street3    string
}

// BeforeSave is a GORM hook that normalizes address data before saving.
func (a *Address) BeforeSave(tx *gorm.DB) (err error) {
	a.RegionCode = strings.ToUpper(a.RegionCode)
	caser := cases.Title(language.English)
	a.City = caser.String(a.City)
	return
}

// FullAddress returns the full, formatted address as a string.
func (a *Address) FullAddress() string {
	parts := []string{a.Street, a.City, a.RegionCode, a.PostalCode, a.Country}
	var validParts []string
	for _, part := range parts {
		if part != "" {
			validParts = append(validParts, part)
		}
	}
	return strings.Join(validParts, ", ")
}
