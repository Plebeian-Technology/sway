package models

import (
	"errors"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupAPIKeyTestDB(t *testing.T) *gorm.DB {
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect to database: %v", err)
	}

	err = db.AutoMigrate(&APIKey{}, &User{}) // Also migrate User for bearer relationship
	if err != nil {
		t.Fatalf("failed to migrate database: %v", err)
	}

	return db
}

func TestAPIKey_BeforeCreate_Success(t *testing.T) {
	db := setupAPIKeyTestDB(t)
	os.Setenv("API_KEY_HMAC_SECRET_KEY", "test-secret")
	defer os.Unsetenv("API_KEY_HMAC_SECRET_KEY")

	email := "test@example.com"
	user := User{Email: &email, WebauthnID: "123", Phone: "1234567"}
	db.Create(&user)

	apiKey := APIKey{
		BearerID:   user.ID,
		BearerType: "User",
		Token:      "my-secret-token",
		Name:       "Test Key",
	}

	result := db.Create(&apiKey)
	assert.NoError(t, result.Error)
	assert.NotEmpty(t, apiKey.TokenDigest)
	assert.NotEqual(t, "my-secret-token", apiKey.TokenDigest)
}

func TestAPIKey_BeforeCreate_NoToken(t *testing.T) {
	db := setupAPIKeyTestDB(t)

	email := "test2@example.com"
	user := User{Email: &email, WebauthnID: "456", Phone: "8901234"}
	db.Create(&user)

	apiKey := APIKey{
		BearerID:   user.ID,
		BearerType: "User",
		Name:       "Test Key No Token",
	}

	result := db.Create(&apiKey)
	assert.Error(t, result.Error)
	assert.Equal(t, "token is required", result.Error.Error())
}

func TestAuthenticateByToken_Success(t *testing.T) {
	db := setupAPIKeyTestDB(t)
	os.Setenv("API_KEY_HMAC_SECRET_KEY", "test-secret")
	defer os.Unsetenv("API_KEY_HMAC_SECRET_KEY")

	email := "test3@example.com"
	user := User{Email: &email, WebauthnID: "789", Phone: "5678901"}
	db.Create(&user)

	rawToken := "authenticate-me"
	apiKey := APIKey{
		BearerID:   user.ID,
		BearerType: "User",
		Token:      rawToken,
		Name:       "Auth Key",
	}
	db.Create(&apiKey)

	// Test AuthenticateByToken
	foundKey, err := AuthenticateByToken(db, rawToken)
	assert.NoError(t, err)
	assert.NotNil(t, foundKey)
	assert.Equal(t, apiKey.ID, foundKey.ID)

	// Test AuthenticateByTokenBang
	foundKeyBang, err := AuthenticateByTokenBang(db, rawToken)
	assert.NoError(t, err)
	assert.NotNil(t, foundKeyBang)
	assert.Equal(t, apiKey.ID, foundKeyBang.ID)
}

func TestAuthenticateByToken_Failure(t *testing.T) {
	db := setupAPIKeyTestDB(t)
	os.Setenv("API_KEY_HMAC_SECRET_KEY", "test-secret")
	defer os.Unsetenv("API_KEY_HMAC_SECRET_KEY")

	// Test AuthenticateByToken with a bad token
	foundKey, err := AuthenticateByToken(db, "bad-token")
	assert.NoError(t, err)
	assert.Nil(t, foundKey)

	// Test AuthenticateByTokenBang with a bad token
	foundKeyBang, err := AuthenticateByTokenBang(db, "bad-token")
	assert.Error(t, err)
	assert.True(t, errors.Is(err, gorm.ErrRecordNotFound))
	assert.Nil(t, foundKeyBang)
}
