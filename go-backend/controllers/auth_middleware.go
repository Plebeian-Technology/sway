package controllers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"sway-go/models"
)

// AuthMiddleware is a placeholder for the authentication middleware.
func AuthMiddleware(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		// For now, we will assume a placeholder for the current user.
		// Later, we will add logic to get the current user from a session.
		// In a real application, this should be a secure, signed session token.
		session, err := c.Cookie("session")
		if err != nil {
			c.Next()
			return
		}

		var user models.User
		if err := db.Where("session = ?", session).First(&user).Error; err != nil {
			c.Redirect(http.StatusFound, "/")
			c.Abort()
			return
		}

		c.Set("user", &user)
		c.Next()
	}
}
