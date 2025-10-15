package controllers

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"github.com/stretchr/testify/assert"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"sway-go/models"
)

func TestInvitesController_Show(t *testing.T) {
	// Set up the router
	r := gin.Default()

	// Set up gonertia
	inertia, err := gonertia.New("<html><body>{{ .inertia }}</body></html>")
	assert.NoError(t, err)

	// Set up database
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	assert.NoError(t, err)

	// Migrate the schema
	db.AutoMigrate(&models.User{}, &models.UserInviter{})

	// Create a user
	user := models.User{FullName: "Test User", WebauthnID: "test_user_invite", Phone: "1234567895"}
	db.Create(&user)

	// Create a user inviter
	userInviter := models.UserInviter{UserID: user.ID, InviterID: 1}
	db.Create(&userInviter)

	invitesController := NewInvitesController(inertia, db)
	r.GET("/invites/:user_id/:invite_uuid", invitesController.Show)

	// Create a request to the show endpoint
	req, _ := http.NewRequest("GET", "/invites/1/123", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusFound, w.Code)
	assert.Equal(t, "/", w.Header().Get("Location"))
}
