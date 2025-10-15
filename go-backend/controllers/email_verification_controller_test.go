package controllers

import (
	"bytes"
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

func TestEmailVerificationController_Create(t *testing.T) {
	// Set up the router
	r := gin.Default()

	// Set up gonertia
	inertia, err := gonertia.New("<html><body>{{ .inertia }}</body></html>")
	assert.NoError(t, err)

	// Set up database
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	assert.NoError(t, err)

	// Migrate the schema
	db.AutoMigrate(&models.User{})

	// Create a user
	user := models.User{FullName: "Test User", WebauthnID: "test_user_email_verification", Phone: "1234567898"}
	db.Create(&user)

	emailVerificationController := NewEmailVerificationController(inertia, db)
	r.Use(func(c *gin.Context) {
		c.Set("user", &user)
		c.Next()
	})
	r.POST("/email_verification", emailVerificationController.Create)

	// Create a request to the create endpoint
	jsonStr := []byte(`{"email":"test@example.com","bill_id":1}`)
	req, _ := http.NewRequest("POST", "/email_verification", bytes.NewBuffer(jsonStr))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusFound, w.Code)
	assert.Equal(t, "/bills/1", w.Header().Get("Location"))

	// Check that the user's email was updated
	var updatedUser models.User
	db.First(&updatedUser, user.ID)
	assert.Equal(t, "test@example.com", *updatedUser.Email)
}
