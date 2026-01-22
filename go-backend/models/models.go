package models

import (
	"time"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

type User struct {
	ID                      uint      `gorm:"primaryKey"`
	Email                   *string   `gorm:"uniqueIndex"`
	Phone                   *string   `gorm:"uniqueIndex"`
	IsPhoneVerified         bool
	IsRegisteredToVote      bool
	IsRegistrationComplete  bool
	IsAdmin                 bool
	WebauthnID              *string   `gorm:"uniqueIndex"`
	FullName                *string

	// New field for notification preference
	SmsNotificationsEnabled bool      `gorm:"default:false"`

	CreatedAt               time.Time
	UpdatedAt               time.Time
}

type SwayLocale struct {
	ID                     uint      `gorm:"primaryKey"`
	City                   string
	State                  string
	Country                string
	CurrentSessionStartDate *time.Time
	TimeZone               *string

	CreatedAt              time.Time
	UpdatedAt              time.Time
}

type District struct {
	ID           uint   `gorm:"primaryKey"`
	Name         string
	SwayLocaleID uint
	SwayLocale   SwayLocale

	CreatedAt    time.Time
	UpdatedAt    time.Time
}

type UserDistrict struct {
	ID         uint `gorm:"primaryKey"`
	UserID     uint
	DistrictID uint

	CreatedAt  time.Time
	UpdatedAt  time.Time
}

type Bill struct {
	ID                       uint      `gorm:"primaryKey"`
	Title                    string
	ScheduledReleaseDateUTC  *time.Time
	IntroducedDateTimeUTC    time.Time
	Active                   *bool
	SwayLocaleID             uint
	SwayLocale               SwayLocale

	BillNotification         *BillNotification

	CreatedAt                time.Time
	UpdatedAt                time.Time
}

// BillNotification tracks if the "Bill of the Week" notification has been sent for a bill (global)
type BillNotification struct {
	ID        uint `gorm:"primaryKey"`
	BillID    uint `gorm:"uniqueIndex"`
	Bill      Bill

	CreatedAt time.Time
	UpdatedAt time.Time
}

type UserVote struct {
	ID        uint `gorm:"primaryKey"`
	UserID    uint
	BillID    uint
	Support   string

	CreatedAt time.Time
	UpdatedAt time.Time
}

// UserBillReminder tracks if a user has been reminded about a specific bill
type UserBillReminder struct {
	ID        uint `gorm:"primaryKey"`
	UserID    uint `gorm:"index"`
	BillID    uint `gorm:"index"`
	SentAt    time.Time

	CreatedAt time.Time
	UpdatedAt time.Time
}

func SetupDB(dsn string) (*gorm.DB, error) {
	db, err := gorm.Open(sqlite.Open(dsn), &gorm.Config{})
	if err != nil {
		return nil, err
	}

	// AutoMigrate will add missing columns and tables
	err = db.AutoMigrate(
		&User{},
		&SwayLocale{},
		&District{},
		&UserDistrict{},
		&Bill{},
		&BillNotification{},
		&UserVote{},
		&UserBillReminder{},
	)
	if err != nil {
		return nil, err
	}

	return db, nil
}
