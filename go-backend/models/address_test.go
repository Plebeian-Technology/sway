package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupTestDB(t *testing.T) *gorm.DB {
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect to database: %v", err)
	}

	err = db.AutoMigrate(&Address{})
	if err != nil {
		t.Fatalf("failed to migrate database: %v", err)
	}

	return db
}

func TestAddress_BeforeSave(t *testing.T) {
	db := setupTestDB(t)

	address := Address{
		City:       "new york",
		RegionCode: "ny",
		Street:     "123 Main St",
		PostalCode: "10001",
		Country:    "US",
	}

	db.Create(&address)

	var savedAddress Address
	db.First(&savedAddress, address.ID)

	assert.Equal(t, "New York", savedAddress.City, "City should be title-cased")
	assert.Equal(t, "NY", savedAddress.RegionCode, "RegionCode should be uppercased")
}

func TestAddress_FullAddress(t *testing.T) {
	address := Address{
		Street:     "123 Main St",
		City:       "New York",
		RegionCode: "NY",
		PostalCode: "10001",
		Country:    "US",
	}

	expected := "123 Main St, New York, NY, 10001, US"
	assert.Equal(t, expected, address.FullAddress(), "FullAddress should return the correctly formatted address")
}

func TestAddress_FullAddress_WithMissingParts(t *testing.T) {
	address := Address{
		Street:     "123 Main St",
		City:       "New York",
		RegionCode: "NY",
	}

	expected := "123 Main St, New York, NY"
	assert.Equal(t, expected, address.FullAddress(), "FullAddress should handle missing parts")
}
