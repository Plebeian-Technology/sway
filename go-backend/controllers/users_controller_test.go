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

func TestUsersController_Update(t *testing.T) {
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
	user := models.User{FullName: "Test User", WebauthnID: "test_user", Phone: "1234567893"}
	db.Create(&user)

	usersController := NewUsersController(inertia, db)
	r.Use(func(c *gin.Context) {
		c.Set("user", &user)
		c.Next()
	})
	r.PATCH("/users/:id", usersController.Update)

	// Create a request to the update endpoint
	jsonStr := []byte(`{"bill_id":1,"full_name":"John Doe"}`)
	req, _ := http.NewRequest("PATCH", "/users/1", bytes.NewBuffer(jsonStr))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusFound, w.Code)
	assert.Equal(t, "/bills/1", w.Header().Get("Location"))

	// Check that the user's name was updated
	var updatedUser models.User
	db.First(&updatedUser, user.ID)
	assert.Equal(t, "John Doe", updatedUser.FullName)
}
