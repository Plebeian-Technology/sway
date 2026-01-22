package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"sway-go/middleware"
	"sway-go/models"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupTestDB() *gorm.DB {
	db, err := gorm.Open(sqlite.Open("file::memory:"), &gorm.Config{})
	if err != nil {
		panic(err)
	}
	db.AutoMigrate(&models.User{})
	return db
}

func TestUpdateNotificationPreferences(t *testing.T) {
	db := setupTestDB()
	handler := UserHandler{DB: db}

	// Create User
	user := models.User{SmsNotificationsEnabled: false}
	db.Create(&user)

	gin.SetMode(gin.TestMode)
	r := gin.Default()

	// Add middleware or set context in test
	r.POST("/api/users/notifications", func(c *gin.Context) {
		// Mock auth
		userID := c.GetHeader("X-User-ID")
		if userID != "" {
			c.Set(middleware.ContextUserIDKey, userID)
		}
		handler.UpdateNotificationPreferences(c)
	})

	// Test Case: Success Enable
	payload := map[string]bool{"sms_notifications_enabled": true}
	jsonValue, _ := json.Marshal(payload)
	req, _ := http.NewRequest("POST", "/api/users/notifications", bytes.NewBuffer(jsonValue))
	req.Header.Set("X-User-ID", strconv.Itoa(int(user.ID)))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var updatedUser models.User
	db.First(&updatedUser, user.ID)
	assert.True(t, updatedUser.SmsNotificationsEnabled)

	// Test Case: Success Disable
	payload = map[string]bool{"sms_notifications_enabled": false}
	jsonValue, _ = json.Marshal(payload)
	req, _ = http.NewRequest("POST", "/api/users/notifications", bytes.NewBuffer(jsonValue))
	req.Header.Set("X-User-ID", strconv.Itoa(int(user.ID)))
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	db.First(&updatedUser, user.ID)
	assert.False(t, updatedUser.SmsNotificationsEnabled)

	// Test Case: User Not Found
	req, _ = http.NewRequest("POST", "/api/users/notifications", bytes.NewBuffer(jsonValue))
	req.Header.Set("X-User-ID", "999")
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusNotFound, w.Code)

	// Test Case: Unauthorized (No Header)
	req, _ = http.NewRequest("POST", "/api/users/notifications", bytes.NewBuffer(jsonValue))
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)

	// Test Case: Invalid Payload
	req, _ = http.NewRequest("POST", "/api/users/notifications", bytes.NewBuffer([]byte("invalid")))
	req.Header.Set("X-User-ID", strconv.Itoa(int(user.ID)))
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
}
