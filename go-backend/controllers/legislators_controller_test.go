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

func TestLegislatorsController_Index(t *testing.T) {
	// Set up the router
	r := gin.Default()

	// Set up gonertia
	inertia, err := gonertia.New("<html><body>{{ .inertia }}</body></html>")
	assert.NoError(t, err)

	// Set up database
	db, err := gorm.Open(sqlite.Open("test.db"), &gorm.Config{})
	assert.NoError(t, err)

	// Migrate the schema
	db.AutoMigrate(&models.Legislator{}, &models.User{}, &models.UserLegislator{})

	// Create a user
	user := models.User{FullName: "Test User"}
	db.Create(&user)

	// Create a legislator
	legislator := models.Legislator{FullName: "Test Legislator"}
	db.Create(&legislator)

	// Create a user-legislator relationship
	userLegislator := models.UserLegislator{UserID: user.ID, LegislatorID: legislator.ID}
	db.Create(&userLegislator)

	legislatorsController := NewLegislatorsController(inertia, db)
	r.GET("/legislators", legislatorsController.Index)

	// Create a request to the index endpoint
	req, _ := http.NewRequest("GET", "/legislators", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "Pages/Legislators")
}

func TestLegislatorsController_Show(t *testing.T) {
	// Set up the router
	r := gin.Default()

	// Set up gonertia
	inertia, err := gonertia.New("<html><body>{{ .inertia }}</body></html>")
	assert.NoError(t, err)

	// Set up database
	db, err := gorm.Open(sqlite.Open("test.db"), &gorm.Config{})
	assert.NoError(t, err)

	// Migrate the schema
	db.AutoMigrate(&models.Legislator{})

	// Create a legislator
	legislator := models.Legislator{FullName: "Test Legislator"}
	db.Create(&legislator)

	legislatorsController := NewLegislatorsController(inertia, db)
	r.GET("/legislators/:id", legislatorsController.Show)

	// Create a request to the show endpoint
	req, _ := http.NewRequest("GET", "/legislators/1", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "Pages/Legislator")
	assert.Contains(t, w.Body.String(), "Test Legislator")
}
