package models

import (
	"time"

	"gorm.io/gorm"
)

// Bill model
type Bill struct {
	gorm.Model
	Title       string
	Description string
	Session     string
	BillNumber  string
	Status      string
}

// BillCosponsor model
type BillCosponsor struct {
	gorm.Model
	BillID       uint
	LegislatorID uint
}

// BillNotification model
type BillNotification struct {
	gorm.Model
	UserID uint
	BillID uint
	SentAt time.Time
}

// BillScore model
type BillScore struct {
	gorm.Model
	BillID uint
	Score  int
}

// BillScoreDistrict model
type BillScoreDistrict struct {
	gorm.Model
	BillScoreID uint
	DistrictID  uint
}

// BillSponsor model
type BillSponsor struct {
	gorm.Model
	BillID       uint
	LegislatorID uint
}

// District model
type District struct {
	gorm.Model
	Name      string
	State     string
	Chamber   string
	Number    string
	SwayLocaleID uint
}

// Invite model
type Invite struct {
	gorm.Model
	Email        string
	Token        string
	InviterID    uint
	InviteeID    uint
	AcceptedAt   time.Time
	OrganizationID uint
}

// Legislator model
type Legislator struct {
	gorm.Model
	FullName  string
	Party     string
	DistrictID uint
}

// LegislatorDistrictScore model
type LegislatorDistrictScore struct {
	gorm.Model
	LegislatorID uint
	DistrictID   uint
	Score        int
}

// LegislatorVote model
type LegislatorVote struct {
	gorm.Model
	LegislatorID uint
	VoteID       uint
	Vote         string
}

// Organization model
type Organization struct {
	gorm.Model
	Name string
}

// OrganizationBillPosition model
type OrganizationBillPosition struct {
	gorm.Model
	OrganizationID uint
	BillID         uint
	Position       string
}

// OrganizationBillPositionChange model
type OrganizationBillPositionChange struct {
	gorm.Model
	OrganizationBillPositionID uint
	OldPosition                string
	NewPosition                string
	ChangedAt                  time.Time
}

// Passkey model
type Passkey struct {
	gorm.Model
	UserID    uint
	PublicKey string
	CredentialID string
}

// PushNotificationSubscription model
type PushNotificationSubscription struct {
	gorm.Model
	UserID     uint
	Endpoint   string
	P256dh     string
	Auth       string
}

// RefreshToken model
type RefreshToken struct {
	gorm.Model
	UserID uint
	Token  string
}

// SwayLocale model
type SwayLocale struct {
	gorm.Model
	Name string
}

// UserAddress model
type UserAddress struct {
	gorm.Model
	UserID    uint
	AddressID uint
}

// UserDistrict model
type UserDistrict struct {
	gorm.Model
	UserID     uint
	DistrictID uint
}

// UserInviter model
type UserInviter struct {
	gorm.Model
	UserID    uint
	InviterID uint
}

// UserLegislator model
type UserLegislator struct {
	gorm.Model
	UserID       uint
	LegislatorID uint
}

// UserLegislatorEmail model
type UserLegislatorEmail struct {
	gorm.Model
	UserID       uint
	LegislatorID uint
	Email        string
	SentAt       time.Time
}

// UserLegislatorScore model
type UserLegislatorScore struct {
	gorm.Model
	UserID       uint
	LegislatorID uint
	Score        int
}

// UserOrganizationMembership model
type UserOrganizationMembership struct {
	gorm.Model
	UserID         uint
	OrganizationID uint
	Role           string
}

// UserOrganizationMembershipInvite model
type UserOrganizationMembershipInvite struct {
	gorm.Model
	UserID         uint
	OrganizationID uint
	InviterID      uint
	AcceptedAt     time.Time
}

// UserVote model
type UserVote struct {
	gorm.Model
	UserID uint
	VoteID uint
	Vote   string
}

// Vote model
type Vote struct {
	gorm.Model
	BillID uint
	Date   time.Time
	Chamber string
	Motion string
}

// User model
type User struct {
	gorm.Model
	CurrentSignInAt      time.Time
	CurrentSignInIP      string
	Email                *string `gorm:"unique"`
	FullName             string
	IsAdmin              bool `gorm:"default:false"`
	IsEmailVerified      bool
	IsPhoneVerified      bool
	IsRegisteredToVote   bool
	IsRegistrationComplete bool
	LastSignInAt         time.Time
	LastSignInIP         string
	Phone                string `gorm:"unique"`
	SignInCount          int    `gorm:"default:0;not null"`
	WebauthnID           string `gorm:"unique"`
}

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

// APIKey model
type APIKey struct {
	gorm.Model
	BearerType    string `gorm:"not null"`
	LastUsedOnUTC time.Time
	Name          string
	TokenDigest   string `gorm:"not null;unique"`
	BearerID      uint   `gorm:"not null"`
}
