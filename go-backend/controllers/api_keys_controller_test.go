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

func TestApiKeysController_Index(t *testing.T) {
	// Set up the router
	r := gin.Default()

	// Set up gonertia
	inertia, err := gonertia.New("<html><body>{{ .inertia }}</body></html>")
	assert.NoError(t, err)

	// Set up database
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	assert.NoError(t, err)

	// Migrate the schema
	db.AutoMigrate(&models.User{}, &models.APIKey{})

	// Create a user
	user := models.User{FullName: "Test User", WebauthnID: "test_user", Phone: "1234567890"}
	db.Create(&user)

	apiKeysController := NewApiKeysController(inertia, db)
	r.Use(func(c *gin.Context) {
		c.Set("user", &user)
		c.Next()
	})
	r.GET("/api_keys", apiKeysController.Index)

	// Create a request to the index endpoint
	req, _ := http.NewRequest("GET", "/api_keys", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "Pages/ApiKeys")
}

func TestApiKeysController_Create(t *testing.T) {
	// Set up the router
	r := gin.Default()

	// Set up gonertia
	inertia, err := gonertia.New("<html><body>{{ .inertia }}</body></html>")
	assert.NoError(t, err)

	// Set up database
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	assert.NoError(t, err)

	// Migrate the schema
	db.AutoMigrate(&models.User{}, &models.APIKey{})

	// Create a user
	user := models.User{FullName: "Test User", WebauthnID: "test_user_create", Phone: "1234567891"}
	db.Create(&user)

	apiKeysController := NewApiKeysController(inertia, db)
	r.Use(func(c *gin.Context) {
		c.Set("user", &user)
		c.Next()
	})
	r.POST("/api_keys", apiKeysController.Create)

	// Create a request to the create endpoint
	req, _ := http.NewRequest("POST", "/api_keys", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusOK, w.Code)
}
