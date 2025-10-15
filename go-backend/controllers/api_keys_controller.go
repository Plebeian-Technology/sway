package controllers

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"gorm.io/gorm"
	"sway-go/models"
)

// ApiKeysController handles requests for API keys.
type ApiKeysController struct {
	Inertia *gonertia.Inertia
	DB      *gorm.DB
}

// NewApiKeysController creates a new ApiKeysController.
func NewApiKeysController(inertia *gonertia.Inertia, db *gorm.DB) *ApiKeysController {
	return &ApiKeysController{Inertia: inertia, DB: db}
}

// Index handles the retrieval of API keys.
func (ac *ApiKeysController) Index(c *gin.Context) {
	user, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	currentUser := user.(*models.User)

	var apiKeys []models.APIKey
	ac.DB.Where("bearer_id = ?", currentUser.ID).Find(&apiKeys)

	ac.Inertia.Render(c.Writer, c.Request, "Pages/ApiKeys", gonertia.Props{
		"apiKeys": apiKeys,
	})
}

// Create handles the creation of an API key.
func (ac *ApiKeysController) Create(c *gin.Context) {
	user, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	currentUser := user.(*models.User)

	var count int64
	ac.DB.Model(&models.APIKey{}).Where("bearer_id = ?", currentUser.ID).Count(&count)

	if count > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "You may only have 1 API Key."})
		return
	}

	token := make([]byte, 32)
	rand.Read(token)
	tokenString := hex.EncodeToString(token)

	hash := sha256.Sum256([]byte(tokenString))
	apiKey := models.APIKey{
		BearerID:   currentUser.ID,
		BearerType: "User",
		TokenDigest: hex.EncodeToString(hash[:]),
	}
	if err := ac.DB.Create(&apiKey).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create API key."})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":          apiKey.ID,
		"bearer_id":   apiKey.BearerID,
		"bearer_type": apiKey.BearerType,
		"token":       tokenString,
	})
}

// Update handles the updating of an API key.
func (ac *ApiKeysController) Update(c *gin.Context) {
	user, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	currentUser := user.(*models.User)

	var apiKey models.APIKey
	if err := ac.DB.Where("bearer_id = ? AND id = ?", currentUser.ID, c.Param("id")).First(&apiKey).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "API key not found."})
		return
	}

	var json struct {
		Name string `json:"name"`
	}
	if err := c.ShouldBindJSON(&json); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := ac.DB.Model(&apiKey).Update("name", json.Name).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update API key."})
		return
	}

	c.Redirect(http.StatusFound, "/api_keys")
}

// Destroy handles the deletion of an API key.
func (ac *ApiKeysController) Destroy(c *gin.Context) {
	user, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	currentUser := user.(*models.User)

	var apiKey models.APIKey
	if err := ac.DB.Where("bearer_id = ? AND id = ?", currentUser.ID, c.Param("id")).First(&apiKey).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "API key not found."})
		return
	}

	if err := ac.DB.Delete(&apiKey).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete API key."})
		return
	}

	c.Redirect(http.StatusFound, "/api_keys")
}
