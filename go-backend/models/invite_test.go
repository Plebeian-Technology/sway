package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupInviteTestDB(t *testing.T) *gorm.DB {
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect to database: %v", err)
	}

	err = db.AutoMigrate(&User{}, &Invite{})
	if err != nil {
		t.Fatalf("failed to migrate database: %v", err)
	}

	return db
}

func TestInvite_Associations(t *testing.T) {
	db := setupInviteTestDB(t)

	inviterEmail := "inviter@example.com"
	inviteeEmail := "invitee@example.com"
	inviter := User{Email: &inviterEmail, WebauthnID: "inviter-webauthn", Phone: "111-222-3333"}
	invitee := User{Email: &inviteeEmail, WebauthnID: "invitee-webauthn", Phone: "444-555-6666"}
	db.Create(&inviter)
	db.Create(&invitee)

	invite := Invite{
		InviterID: inviter.ID,
		InviteeID: invitee.ID,
	}
	db.Create(&invite)

	var foundInvite Invite
	err := db.Preload("Inviter").Preload("Invitee").First(&foundInvite, invite.ID).Error
	assert.NoError(t, err)

	assert.Equal(t, inviter.ID, foundInvite.Inviter.ID)
	assert.Equal(t, inviter.Email, foundInvite.Inviter.Email)
	assert.Equal(t, invitee.ID, foundInvite.Invitee.ID)
	assert.Equal(t, invitee.Email, foundInvite.Invitee.Email)
}
