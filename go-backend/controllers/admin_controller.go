package controllers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"gorm.io/gorm"
	"sway-go/models"
)

// AdminController handles requests for the admin panel.
type AdminController struct {
	Inertia *gonertia.Inertia
	DB      *gorm.DB
}

// NewAdminController creates a new AdminController.
func NewAdminController(inertia *gonertia.Inertia, db *gorm.DB) *AdminController {
	return &AdminController{Inertia: inertia, DB: db}
}

// AdminMiddleware is a middleware function that verifies that the user is an admin.
func (ac *AdminController) AdminMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// For now, we will assume a placeholder for the current user.
		// Later, we will add logic to get the current user.
		user, exists := c.Get("user")
		if !exists {
			c.Redirect(http.StatusFound, "/")
			c.Abort()
			return
		}

		u := user.(*models.User)
		if !u.IsAdmin {
			c.Redirect(http.StatusFound, "/")
			c.Abort()
			return
		}

		c.Next()
	}
}
