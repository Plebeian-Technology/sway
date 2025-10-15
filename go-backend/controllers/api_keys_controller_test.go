package controllers

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"github.com/stretchr/testify/assert"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"sway-go/models"
)

func TestApiKeysController_Update(t *testing.T) {
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
	user := models.User{FullName: "Test User", WebauthnID: "test_user_api_key_update", Phone: "1234567896"}
	db.Create(&user)

	// Create an API key
	apiKey := models.APIKey{BearerID: user.ID, BearerType: "User", TokenDigest: "test_destroy"}
	db.Create(&apiKey)

	apiKeysController := NewApiKeysController(inertia, db)
	r.Use(func(c *gin.Context) {
		c.Set("user", &user)
		c.Next()
	})
	r.PATCH("/api_keys/:id", apiKeysController.Update)

	// Create a request to the update endpoint
	jsonStr := []byte(`{"name":"Test API Key"}`)
	req, _ := http.NewRequest("PATCH", "/api_keys/"+strconv.Itoa(int(apiKey.ID)), bytes.NewBuffer(jsonStr))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusFound, w.Code)
	assert.Equal(t, "/api_keys", w.Header().Get("Location"))

	// Check that the API key's name was updated
	var updatedApiKey models.APIKey
	db.First(&updatedApiKey, apiKey.ID)
	assert.Equal(t, "Test API Key", updatedApiKey.Name)
}

func TestApiKeysController_Destroy(t *testing.T) {
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
	user := models.User{FullName: "Test User", WebauthnID: "test_user_api_key_destroy", Phone: "1234567897"}
	db.Create(&user)

	// Create an API key
	apiKey := models.APIKey{BearerID: user.ID, BearerType: "User", TokenDigest: "test"}
	db.Create(&apiKey)

	apiKeysController := NewApiKeysController(inertia, db)
	r.Use(func(c *gin.Context) {
		c.Set("user", &user)
		c.Next()
	})
	r.DELETE("/api_keys/:id", apiKeysController.Destroy)

	// Create a request to the destroy endpoint
	req, _ := http.NewRequest("DELETE", "/api_keys/"+strconv.Itoa(int(apiKey.ID)), nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusFound, w.Code)
	assert.Equal(t, "/api_keys", w.Header().Get("Location"))

	// Check that the API key was deleted
	var deletedApiKey models.APIKey
	result := db.First(&deletedApiKey, apiKey.ID)
	assert.Error(t, result.Error)
}
