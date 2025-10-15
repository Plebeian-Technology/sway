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

func TestAdminController_AdminMiddleware_NotAdmin(t *testing.T) {
	// Set up the router
	r := gin.Default()

	// Set up gonertia
	inertia, err := gonertia.New("<html><body>{{ .inertia }}</body></html>")
	assert.NoError(t, err)

	// Set up database
	db, err := gorm.Open(sqlite.Open("test.db"), &gorm.Config{})
	assert.NoError(t, err)

	// Migrate the schema
	db.AutoMigrate(&models.User{})

	// Create a user
	user := models.User{IsAdmin: false, WebauthnID: "test_not_admin", Phone: "1234567890"}
	db.Create(&user)

	adminController := NewAdminController(inertia, db)
	r.Use(func(c *gin.Context) {
		c.Set("user", &user)
		c.Next()
	})
	r.GET("/admin", adminController.AdminMiddleware(), func(c *gin.Context) {
		c.String(http.StatusOK, "Success")
	})

	// Create a request to the admin endpoint
	req, _ := http.NewRequest("GET", "/admin", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusFound, w.Code)
	assert.Equal(t, "/", w.Header().Get("Location"))
}

func TestAdminController_AdminMiddleware_Admin(t *testing.T) {
	// Set up the router
	r := gin.Default()

	// Set up gonertia
	inertia, err := gonertia.New("<html><body>{{ .inertia }}</body></html>")
	assert.NoError(t, err)

	// Set up database
	db, err := gorm.Open(sqlite.Open("test.db"), &gorm.Config{})
	assert.NoError(t, err)

	// Migrate the schema
	db.AutoMigrate(&models.User{})

	// Create a user
	user := models.User{IsAdmin: true, WebauthnID: "test_admin", Phone: "1234567891"}
	db.Create(&user)

	adminController := NewAdminController(inertia, db)
	r.Use(func(c *gin.Context) {
		c.Set("user", &user)
		c.Next()
	})
	r.GET("/admin", adminController.AdminMiddleware(), func(c *gin.Context) {
		c.String(http.StatusOK, "Success")
	})

	// Create a request to the admin endpoint
	req, _ := http.NewRequest("GET", "/admin", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "Success", w.Body.String())
}
