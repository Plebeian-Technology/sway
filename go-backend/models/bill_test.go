package models

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupBillTestDB(t *testing.T) *gorm.DB {
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect to database: %v", err)
	}

	err = db.AutoMigrate(
		&Bill{},
		&Legislator{},
		&SwayLocale{},
		&BillScore{},
		&Vote{},
	)
	if err != nil {
		t.Fatalf("failed to migrate database: %v", err)
	}

	return db
}

func TestBill_BeforeSave_DowncaseStatus(t *testing.T) {
	db := setupBillTestDB(t)

	// Test valid status
	swayLocale1 := SwayLocale{Name: "Test Locale 1"}
	db.Create(&swayLocale1)
	bill1 := Bill{
		Title:                 "Test Bill 1",
		Status:                "Passed",
		Category:              "Test",
		Chamber:               "House",
		IntroducedDateTimeUTC: time.Now(),
		ExternalID:            "HB1",
		LegislatorID:          1,
		SwayLocaleID:          swayLocale1.ID,
	}
	db.Create(&bill1)
	assert.Equal(t, "passed", bill1.Status)

	// Test invalid status
	swayLocale2 := SwayLocale{Name: "Test Locale 2"}
	db.Create(&swayLocale2)
	bill2 := Bill{
		Title:                 "Test Bill 2",
		Status:                "InvalidStatus",
		Category:              "Test",
		Chamber:               "House",
		IntroducedDateTimeUTC: time.Now(),
		ExternalID:            "HB2",
		LegislatorID:          1,
		SwayLocaleID:          swayLocale2.ID,
	}
	db.Create(&bill2)
	assert.Equal(t, "", bill2.Status)
}

func TestBill_Associations(t *testing.T) {
	db := setupBillTestDB(t)

	legislator := Legislator{FullName: "John Doe"}
	swayLocale := SwayLocale{Name: "Test Locale 3"}
	db.Create(&legislator)
	db.Create(&swayLocale)

	bill := Bill{
		Title:                 "Association Test Bill",
		Category:              "Test",
		Chamber:               "Senate",
		IntroducedDateTimeUTC: time.Now(),
		ExternalID:            "SB1",
		LegislatorID:          legislator.ID,
		SwayLocaleID:          swayLocale.ID,
	}
	db.Create(&bill)

	// Create associated records
	db.Create(&BillScore{BillID: bill.ID, Score: 100})
	db.Create(&Vote{BillID: bill.ID, Motion: "Yea"})

	var foundBill Bill
	err := db.
		Preload("Legislator").
		Preload("SwayLocale").
		Preload("BillScore").
		Preload("Votes").
		First(&foundBill, bill.ID).Error
	assert.NoError(t, err)

	// Assert associations
	assert.Equal(t, legislator.ID, foundBill.Legislator.ID)
	assert.Equal(t, swayLocale.ID, foundBill.SwayLocale.ID)
	assert.NotNil(t, foundBill.BillScore)
	assert.Equal(t, 100, foundBill.BillScore.Score)
	assert.Len(t, foundBill.Votes, 1)
	assert.Equal(t, "Yea", foundBill.Votes[0].Motion)
}
