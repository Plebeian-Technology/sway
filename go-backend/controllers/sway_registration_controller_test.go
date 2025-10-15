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

func TestSwayRegistrationController_Index(t *testing.T) {
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
	user := models.User{FullName: "Test User", WebauthnID: "test_user_sway_registration", Phone: "1234567899"}
	db.Create(&user)

	swayRegistrationController := NewSwayRegistrationController(inertia, db)
	r.Use(func(c *gin.Context) {
		c.Set("user", &user)
		c.Next()
	})
	r.GET("/sway_registration", swayRegistrationController.Index)

	// Create a request to the index endpoint
	req, _ := http.NewRequest("GET", "/sway_registration", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "Pages/Registration")
}

func TestSwayRegistrationController_Create(t *testing.T) {
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
	user := models.User{FullName: "Test User", WebauthnID: "test_user_sway_registration_create", Phone: "1234567900"}
	db.Create(&user)

	swayRegistrationController := NewSwayRegistrationController(inertia, db)
	r.Use(func(c *gin.Context) {
		c.Set("user", &user)
		c.Next()
	})
	r.POST("/sway_registration", swayRegistrationController.Create)

	// Create a request to the create endpoint
	req, _ := http.NewRequest("POST", "/sway_registration", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusFound, w.Code)
	assert.Equal(t, "/legislators", w.Header().Get("Location"))
}
