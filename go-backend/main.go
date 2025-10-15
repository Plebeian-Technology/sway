package main

import (
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"sway-go/controllers"
	"sway-go/models"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func main() {
	// Set up Gin
	r := gin.Default()

	// Set up gonertia
	inertia, err := gonertia.New("<html><body>{{ .inertia }}</body></html>")
	if err != nil {
		log.Fatal(err)
	}

	// Set up database
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "test.db"
	}
	db, err := gorm.Open(sqlite.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatal("failed to connect database")
	}

	// Migrate the schema
	db.AutoMigrate(&models.User{}, &models.Address{}, &models.APIKey{}, &models.Bill{}, &models.BillCosponsor{}, &models.BillNotification{}, &models.BillScore{}, &models.BillScoreDistrict{}, &models.BillSponsor{}, &models.District{}, &models.Invite{}, &models.Legislator{}, &models.LegislatorDistrictScore{}, &models.LegislatorVote{}, &models.Organization{}, &models.OrganizationBillPosition{}, &models.OrganizationBillPositionChange{}, &models.Passkey{}, &models.PushNotificationSubscription{}, &models.RefreshToken{}, &models.SwayLocale{}, &models.UserAddress{}, &models.UserDistrict{}, &models.UserInviter{}, &models.UserLegislator{}, &models.UserLegislatorEmail{}, &models.UserLegislatorScore{}, &models.UserOrganizationMembership{}, &models.UserOrganizationMembershipInvite{}, &models.UserVote{}, &models.Vote{})

	// Set up controllers
	homeController := controllers.NewHomeController(inertia)
	usersController := controllers.NewUsersController(inertia, db)
	legislatorsController := controllers.NewLegislatorsController(inertia, db)
	billsController := controllers.NewBillsController(inertia, db)
	adminController := controllers.NewAdminController(inertia, db)
	apiKeysController := controllers.NewApiKeysController(inertia, db)
	invitesController := controllers.NewInvitesController(inertia, db)
	emailVerificationController := controllers.NewEmailVerificationController(inertia, db)
	phoneVerificationController := controllers.NewPhoneVerificationController(inertia, db)
	swayRegistrationController := controllers.NewSwayRegistrationController(inertia, db)

	// Set up routes
	r.Use(controllers.AuthMiddleware(db))

	r.GET("/", homeController.Index)
	r.PATCH("/users/:id", usersController.Update)
	r.GET("/legislators", legislatorsController.Index)
	r.GET("/legislators/:id", legislatorsController.Show)
	r.GET("/bills", billsController.Index)
	r.GET("/bills/:id", billsController.Show)
	r.GET("/api_keys", apiKeysController.Index)
	r.POST("/api_keys", apiKeysController.Create)
	r.PATCH("/api_keys/:id", apiKeysController.Update)
	r.DELETE("/api_keys/:id", apiKeysController.Destroy)
	r.GET("/invites/:user_id/:invite_uuid", invitesController.Show)
	r.POST("/email_verification", emailVerificationController.Create)
	r.PATCH("/email_verification", emailVerificationController.Update)
	r.DELETE("/email_verification", emailVerificationController.Destroy)
	r.POST("/phone_verification", phoneVerificationController.Create)
	r.PATCH("/phone_verification", phoneVerificationController.Update)
	r.GET("/sway_registration", swayRegistrationController.Index)
	r.POST("/sway_registration", swayRegistrationController.Create)

	// Admin routes
	admin := r.Group("/admin")
	admin.Use(adminController.AdminMiddleware())
	{
		admin.GET("/bills/new", billsController.New)
		admin.GET("/bills/:id/edit", billsController.Edit)
		admin.POST("/bills", billsController.Create)
		admin.PATCH("/bills/:id", billsController.Update)
		admin.DELETE("/bills/:id", billsController.Destroy)
	}

	// Start the server
	if err := http.ListenAndServe(":8080", r); err != nil {
		log.Fatal(err)
	}
}
