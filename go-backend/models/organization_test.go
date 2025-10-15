package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupOrganizationTestDB(t *testing.T) *gorm.DB {
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect to database: %v", err)
	}

	err = db.AutoMigrate(
		&Organization{},
		&SwayLocale{},
		&UserOrganizationMembership{},
		&OrganizationBillPosition{},
	)
	if err != nil {
		t.Fatalf("failed to migrate database: %v", err)
	}

	return db
}

func TestOrganization_Associations(t *testing.T) {
	db := setupOrganizationTestDB(t)

	swayLocale := SwayLocale{Name: "Test Locale"}
	db.Create(&swayLocale)

	organization := Organization{
		Name:         "Test Organization",
		SwayLocaleID: swayLocale.ID,
	}
	db.Create(&organization)

	// Create associated records
	db.Create(&UserOrganizationMembership{OrganizationID: organization.ID, UserID: 1})
	db.Create(&OrganizationBillPosition{OrganizationID: organization.ID, BillID: 1, Position: "Support"})

	var foundOrganization Organization
	err := db.
		Preload("SwayLocale").
		Preload("UserOrganizationMemberships").
		Preload("OrganizationBillPositions").
		First(&foundOrganization, organization.ID).Error
	assert.NoError(t, err)

	// Assert associations
	assert.Equal(t, swayLocale.ID, foundOrganization.SwayLocale.ID)
	assert.Len(t, foundOrganization.UserOrganizationMemberships, 1)
	assert.Len(t, foundOrganization.OrganizationBillPositions, 1)
}
