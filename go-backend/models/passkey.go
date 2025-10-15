package models

import "gorm.io/gorm"

// Passkey model
type Passkey struct {
	gorm.Model
	UserID    uint
	PublicKey string
	CredentialID string
}
