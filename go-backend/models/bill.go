package models

import (
	"strings"
	"time"

	"gorm.io/gorm"
)

// BillStatus represents the possible statuses for a Bill
type BillStatus string

const (
	StatusPassed   BillStatus = "passed"
	StatusFailed   BillStatus = "failed"
	StatusCommittee BillStatus = "committee"
	StatusVetoed   BillStatus = "vetoed"
)

var validStatuses = map[BillStatus]bool{
	StatusPassed:   true,
	StatusFailed:   true,
	StatusCommittee: true,
	StatusVetoed:   true,
}

// Bill model
type Bill struct {
	gorm.Model
	Active                   bool
	AudioBucketPath          string
	AudioByLine              string
	Category                 string    `gorm:"not null"`
	Chamber                  string    `gorm:"not null"`
	ExternalVersion          string
	HouseVoteDateTimeUTC     time.Time
	IntroducedDateTimeUTC    time.Time `gorm:"not null"`
	Link                     string
	ScheduledReleaseDateUTC  time.Time
	SenateVoteDateTimeUTC    time.Time
	Status                   string
	Summary                  string `gorm:"type:text"`
	Title                    string `gorm:"not null"`
	ExternalID               string `gorm:"not null;uniqueIndex:idx_bills_on_external_id_and_sway_locale_id"`
	LegislatorID             uint   `gorm:"not null"`
	SwayLocaleID             uint   `gorm:"not null;uniqueIndex:idx_bills_on_external_id_and_sway_locale_id;uniqueIndex:idx_bills_on_scheduled_release_date_utc_and_sway_locale_id"`

	// Associations
	Legislator                Legislator
	SwayLocale                SwayLocale
	BillScore                 BillScore                 `gorm:"foreignKey:BillID"`
	BillNotification          BillNotification          `gorm:"foreignKey:BillID"`
	BillCosponsors            []BillCosponsor           `gorm:"foreignKey:BillID"`
	Votes                     []Vote                    `gorm:"foreignKey:BillID"`
	OrganizationBillPositions []OrganizationBillPosition `gorm:"foreignKey:BillID"`
}

// BeforeSave is a GORM hook that downcases the status before saving.
func (b *Bill) BeforeSave(tx *gorm.DB) (err error) {
	if b.Status != "" {
		lowerStatus := BillStatus(strings.ToLower(b.Status))
		if validStatuses[lowerStatus] {
			b.Status = string(lowerStatus)
		} else {
			// In the Rails app, this logs a warning and sets status to nil.
			// Replicating that behavior.
			b.Status = ""
			tx.Logger.Warn(tx.Statement.Context, "Bill.BeforeSave - received status of %s is NOT valid. Should be one of passed, failed, committee, vetoed", b.Status)
		}
	}
	return
}
