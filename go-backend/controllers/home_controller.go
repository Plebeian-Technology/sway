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
	// For now, we will assume the user is not logged in.
	// Later, we will add logic to check for the current user.
	// user, _ := c.Get("user")

	// For the purpose of this translation, we will assume user is nil
	var user *models.User

	if user != nil {
		if user.IsRegistrationComplete {
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
