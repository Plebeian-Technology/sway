package controllers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"gorm.io/gorm"
	"sway-go/models"
)

// InvitesController handles requests for invites.
type InvitesController struct {
	Inertia *gonertia.Inertia
	DB      *gorm.DB
}

// NewInvitesController creates a new InvitesController.
func NewInvitesController(inertia *gonertia.Inertia, db *gorm.DB) *InvitesController {
	return &InvitesController{Inertia: inertia, DB: db}
}

// Show handles the retrieval of an invite.
func (ic *InvitesController) Show(c *gin.Context) {
	var userInviter models.UserInviter
	if err := ic.DB.Where("user_id = ? AND invite_uuid = ?", c.Param("user_id"), c.Param("invite_uuid")).First(&userInviter).Error; err != nil {
		c.Redirect(http.StatusFound, "/")
		return
	}

	c.SetCookie("invited_by", c.Param("user_id"), 3600*24*30, "", "", false, true)
	c.Redirect(http.StatusFound, "/")
}
