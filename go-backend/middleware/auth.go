package middleware

import (
	"github.com/gin-gonic/gin"
)

const ContextUserIDKey = "userID"

// MockAuthMiddleware is a placeholder for actual authentication.
// It allows passing user_id via header X-User-ID for testing purposes.
// IN PRODUCTION: Replace this with actual session/token validation.
func MockAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Try to get user ID from header
		userID := c.GetHeader("X-User-ID")
		if userID != "" {
			c.Set(ContextUserIDKey, userID)
		}
		c.Next()
	}
}
