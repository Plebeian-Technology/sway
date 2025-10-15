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

func TestBillsController_Index(t *testing.T) {
	// Set up the router
	r := gin.Default()

	// Set up gonertia
	inertia, err := gonertia.New("<html><body>{{ .inertia }}</body></html>")
	assert.NoError(t, err)

	// Set up database
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	assert.NoError(t, err)

	// Migrate the schema
	db.AutoMigrate(&models.Bill{}, &models.User{}, &models.UserBill{})

	// Create a user
	user := models.User{FullName: "Test User", WebauthnID: "test_user_bill", Phone: "1234567894"}
	db.Create(&user)

	// Create a bill
	bill := models.Bill{Title: "Test Bill"}
	db.Create(&bill)

	// Create a user-bill relationship
	userBill := models.UserBill{UserID: user.ID, BillID: bill.ID}
	db.Create(&userBill)

	billsController := NewBillsController(inertia, db)
	r.Use(func(c *gin.Context) {
		c.Set("user", &user)
		c.Next()
	})
	r.GET("/bills", billsController.Index)

	// Create a request to the index endpoint
	req, _ := http.NewRequest("GET", "/bills", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "Pages/Bills")
}

func TestBillsController_Show(t *testing.T) {
	// Set up the router
	r := gin.Default()

	// Set up gonertia
	inertia, err := gonertia.New("<html><body>{{ .inertia }}</body></html>")
	assert.NoError(t, err)

	// Set up database
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	assert.NoError(t, err)

	// Migrate the schema
	db.AutoMigrate(&models.Bill{})

	// Create a bill
	bill := models.Bill{Title: "Test Bill"}
	db.Create(&bill)

	billsController := NewBillsController(inertia, db)
	r.GET("/bills/:id", billsController.Show)

	// Create a request to the show endpoint
	req, _ := http.NewRequest("GET", "/bills/1", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Check the response
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "Pages/Bill")
}
