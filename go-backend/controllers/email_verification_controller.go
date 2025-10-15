package controllers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"gorm.io/gorm"
	"sway-go/models"
)

// EmailVerificationController handles requests for email verification.
type EmailVerificationController struct {
	Inertia *gonertia.Inertia
	DB      *gorm.DB
}

// NewEmailVerificationController creates a new EmailVerificationController.
func NewEmailVerificationController(inertia *gonertia.Inertia, db *gorm.DB) *EmailVerificationController {
	return &EmailVerificationController{Inertia: inertia, DB: db}
}

// Create handles the creation of an email verification.
func (evc *EmailVerificationController) Create(c *gin.Context) {
	// For now, we will assume a placeholder for the current user.
	// Later, we will add logic to get the current user.
	user, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	currentUser := user.(*models.User)

	var json struct {
		Email  string `json:"email"`
		BillID int    `json:"bill_id"`
	}
	if err := c.ShouldBindJSON(&json); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// In a real application, this would send an email with a verification code.
	// For now, we will just update the user's email.
	if err := evc.DB.Model(&currentUser).Update("email", json.Email).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update email."})
		return
	}

	c.Redirect(http.StatusFound, "/bills/"+strconv.Itoa(json.BillID))
}

// Update handles the updating of an email verification.
func (evc *EmailVerificationController) Update(c *gin.Context) {
	// For now, we will assume a placeholder for the current user.
	// Later, we will add logic to get the current user.
	user, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	currentUser := user.(*models.User)

	var json struct {
		Code   string `json:"code"`
		BillID int    `json:"bill_id"`
	}
	if err := c.ShouldBindJSON(&json); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// In a real application, this would verify the code against the one sent to the user.
	// For now, we will just mark the email as verified.
	if err := evc.DB.Model(&currentUser).Update("is_email_verified", true).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update email verification."})
		return
	}

	c.Redirect(http.StatusFound, "/bills/"+strconv.Itoa(json.BillID))
}

// Destroy handles the deletion of an email verification.
func (evc *EmailVerificationController) Destroy(c *gin.Context) {
	// For now, we will assume a placeholder for the current user.
	// Later, we will add logic to get the current user.
	user, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	currentUser := user.(*models.User)

	if err := evc.DB.Model(&currentUser).Updates(map[string]interface{}{"email": nil, "is_email_verified": false}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to reset email verification."})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}
