package main

import (
	"log"
	"os"
	"time"

	"sway-go/handlers"
	"sway-go/middleware"
	"sway-go/models"
	"sway-go/notifications"

	"github.com/gin-gonic/gin"
)

func main() {
	// Database setup
	// Use environment variable for DSN or default to local sqlite
	dsn := os.Getenv("DATABASE_DSN")
	if dsn == "" {
		dsn = "sway_go.db" // Local dev db for go-backend
	}

	db, err := models.SetupDB(dsn)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// Notification Service
	notifier := &notifications.TwilioNotificationService{
		AccountSID: os.Getenv("TWILIO_ACCOUNT_SID"),
		AuthToken:  os.Getenv("TWILIO_AUTH_TOKEN"),
		FromPhone:  os.Getenv("TWILIO_FROM_PHONE"),
	}

	// Background Worker
	worker := notifications.NewWorker(db, notifier)
	go func() {
		// Run checks immediately on startup for demonstration
		worker.RunChecks()

		ticker := time.NewTicker(1 * time.Hour) // Run every hour
		defer ticker.Stop()

		for range ticker.C {
			worker.RunChecks()
		}
	}()

	// Gin setup
	r := gin.Default()

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status": "ok",
		})
	})

	userHandler := &handlers.UserHandler{DB: db}

	api := r.Group("/api")
	api.Use(middleware.MockAuthMiddleware())
	{
		api.POST("/users/notifications", userHandler.UpdateNotificationPreferences)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	r.Run(":" + port)
}
