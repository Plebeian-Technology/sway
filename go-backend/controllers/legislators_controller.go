package controllers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"gorm.io/gorm"
	"sway-go/models"
)

// LegislatorsController handles requests for legislators.
type LegislatorsController struct {
	Inertia *gonertia.Inertia
	DB      *gorm.DB
}

// NewLegislatorsController creates a new LegislatorsController.
func NewLegislatorsController(inertia *gonertia.Inertia, db *gorm.DB) *LegislatorsController {
	return &LegislatorsController{Inertia: inertia, DB: db}
}

// Index handles the retrieval of legislators.
func (lc *LegislatorsController) Index(c *gin.Context) {
	// For now, we will assume a placeholder for the current user.
	// Later, we will add logic to get the current user.
	currentUser := &models.User{}
	if err := lc.DB.First(currentUser, 1).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get user."})
		return
	}

	var legislators []models.Legislator
	lc.DB.Joins("JOIN user_legislators ON user_legislators.legislator_id = legislators.id").Where("user_legislators.user_id = ?", currentUser.ID).Find(&legislators)

	lc.Inertia.Render(c.Writer, c.Request, "Pages/Legislators", gonertia.Props{
		"legislators": legislators,
	})
}

// Show handles the retrieval of a single legislator.
func (lc *LegislatorsController) Show(c *gin.Context) {
	var legislator models.Legislator
	if err := lc.DB.First(&legislator, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Legislator not found."})
		return
	}

	lc.Inertia.Render(c.Writer, c.Request, "Pages/Legislator", gonertia.Props{
		"legislator": legislator,
	})
}
