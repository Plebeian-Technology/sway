package models

import (
	"crypto/hmac"
	"crypto/sha512"
	"encoding/hex"
	"errors"
	"os"
	"time"

	"gorm.io/gorm"
)

// APIKey model
type APIKey struct {
	gorm.Model
	BearerType    string `gorm:"not null"`
	LastUsedOnUTC time.Time
	Name          string
	TokenDigest   string `gorm:"not null;unique"`
	BearerID      uint   `gorm:"not null"`
	Token         string `gorm:"-"` // Virtual attribute for raw token value
}

// BeforeCreate is a GORM hook that generates the token digest before creating a new APIKey record
func (apiKey *APIKey) BeforeCreate(tx *gorm.DB) (err error) {
	if apiKey.Token == "" {
		return errors.New("token is required")
	}

	apiKey.TokenDigest, err = generateTokenHMACDigest(apiKey.Token)
	return
}

// AuthenticateByToken finds an API key by its token
func AuthenticateByToken(db *gorm.DB, token string) (*APIKey, error) {
	return authenticateByToken(db, token, false)
}

// AuthenticateByToken finds an API key by its token and returns an error if not found
func AuthenticateByTokenBang(db *gorm.DB, token string) (*APIKey, error) {
	return authenticateByToken(db, token, true)
}

func authenticateByToken(db *gorm.DB, token string, bang bool) (*APIKey, error) {
	digest, err := generateTokenHMACDigest(token)
	if err != nil {
		return nil, err
	}

	var apiKey APIKey
	var result *gorm.DB
	if bang {
		result = db.Where("token_digest = ?", digest).First(&apiKey)
	} else {
		result = db.Where("token_digest = ?", digest).Limit(1).Find(&apiKey)
	}

	if result.Error != nil {
		return nil, result.Error
	}

	if result.RowsAffected == 0 {
		return nil, nil // Return nil if no record is found
	}

	return &apiKey, nil
}

func generateTokenHMACDigest(token string) (string, error) {
	hmacSecretKey := os.Getenv("API_KEY_HMAC_SECRET_KEY")
	if hmacSecretKey == "" {
		// In test environment, use a default value
		if os.Getenv("GO_ENV") == "test" {
			hmacSecretKey = "test"
		} else {
			return "", errors.New("API_KEY_HMAC_SECRET_KEY is not set")
		}
	}

	mac := hmac.New(sha512.New, []byte(hmacSecretKey))
	_, err := mac.Write([]byte(token))
	if err != nil {
		return "", err
	}
	return hex.EncodeToString(mac.Sum(nil)), nil
}
