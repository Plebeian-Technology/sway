package controllers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"gorm.io/gorm"
	"sway-go/models"
)

// ApplicationController handles shared logic for all controllers.
type ApplicationController struct {
	Inertia *gonertia.Inertia
	DB      *gorm.DB
}

// NewApplicationController creates a new ApplicationController.
func NewApplicationController(inertia *gonertia.Inertia, db *gorm.DB) *ApplicationController {
	return &ApplicationController{Inertia: inertia, DB: db}
}

// UsersController handles requests for users.
type UsersController struct {
	Inertia *gonertia.Inertia
	DB      *gorm.DB
}

// NewUsersController creates a new UsersController.
func NewUsersController(inertia *gonertia.Inertia, db *gorm.DB) *UsersController {
	return &UsersController{Inertia: inertia, DB: db}
}

// Create handles the creation of user details.
func (uc *UsersController) Create(c *gin.Context) {
	// For now, we will assume a placeholder for the current user.
	// Later, we will add logic to get the current user.
	currentUser := &models.User{}
	if err := uc.DB.First(currentUser, 1).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get user."})
		return
	}

	var json struct {
		BillID   int    `json:"bill_id"`
		FullName string `json:"full_name"`
	}

	if err := c.ShouldBindJSON(&json); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	redirectPath := "/bills/" + strconv.Itoa(json.BillID)

	if err := uc.DB.Model(&currentUser).Update("full_name", json.FullName).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save your name. Please try again."})
		return
	}

	c.Redirect(http.StatusFound, redirectPath)
}


// LegislatorsController handles requests for legislators.
type LegislatorsController struct {
	Inertia *gonertia.Inertia
	DB      *gorm.DB
}

// NewLegislatorsController creates a new LegislatorsController.
func NewLegislatorsController(inertia *gonertia.Inertia, db *gorm.DB) *LegislatorsController {
	return &LegislatorsController{Inertia: inertia, DB: db}
}

// Placeholder for other controllers
// ...
