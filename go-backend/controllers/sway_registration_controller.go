package controllers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"gorm.io/gorm"
	"sway-go/models"
)

// SwayRegistrationController handles requests for sway registration.
type SwayRegistrationController struct {
	Inertia *gonertia.Inertia
	DB      *gorm.DB
}

// NewSwayRegistrationController creates a new SwayRegistrationController.
func NewSwayRegistrationController(inertia *gonertia.Inertia, db *gorm.DB) *SwayRegistrationController {
	return &SwayRegistrationController{Inertia: inertia, DB: db}
}

// Index handles the retrieval of the registration page.
func (src *SwayRegistrationController) Index(c *gin.Context) {
	user, exists := c.Get("user")
	if !exists {
		c.Redirect(http.StatusFound, "/")
		return
	}
	currentUser := user.(*models.User)

	if currentUser.IsRegistrationComplete {
		c.Redirect(http.StatusFound, "/legislators")
		return
	}

	src.Inertia.Render(c.Writer, c.Request, "Pages/Registration", nil)
}

// Create handles the creation of a sway registration.
func (src *SwayRegistrationController) Create(c *gin.Context) {
	user, exists := c.Get("user")
	if !exists {
		c.Redirect(http.StatusFound, "/")
		return
	}
	currentUser := user.(*models.User)

	if currentUser.IsRegistrationComplete {
		c.Redirect(http.StatusFound, "/legislators")
		return
	}

	// For now, we will assume a placeholder for the registration logic.
	// Later, we will add logic to find representatives and create user legislators.
	c.Redirect(http.StatusFound, "/legislators")
}
