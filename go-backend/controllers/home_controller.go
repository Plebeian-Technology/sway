package controllers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"sway-go/models"
)

// HomeController handles requests for the home page.
type HomeController struct {
	Inertia *gonertia.Inertia
}

// NewHomeController creates a new HomeController.
func NewHomeController(inertia *gonertia.Inertia) *HomeController {
	return &HomeController{Inertia: inertia}
}

// Index renders the home page.
func (hc *HomeController) Index(c *gin.Context) {
	// For now, we will assume a placeholder for the current user.
	// Later, we will add logic to get the current user.
	user, exists := c.Get("user")
	if !exists {
		user = nil
	}

	if user != nil {
		u := user.(*models.User)
		if u.IsRegistrationComplete {
			c.Redirect(http.StatusFound, "/legislators")
			return
		}
		c.Redirect(http.StatusFound, "/sway_registration")
		return
	}

	hc.Inertia.Render(c.Writer, c.Request, "Pages/Home", gonertia.Props{
		"name":      "Sway",
		"isBubbles": true,
		"params":    c.Request.URL.Query(),
	})
}
