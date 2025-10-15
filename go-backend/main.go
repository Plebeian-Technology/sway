package main

import (
	"log"
	"net/http"

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
	db, err := gorm.Open(sqlite.Open("test.db"), &gorm.Config{})
	if err != nil {
		log.Fatal("failed to connect database")
	}

	// Migrate the schema
	db.AutoMigrate(&models.User{}, &models.Address{}, &models.APIKey{}, &models.Bill{}, &models.BillCosponsor{}, &models.BillNotification{}, &models.BillScore{}, &models.BillScoreDistrict{}, &models.BillSponsor{}, &models.District{}, &models.Invite{}, &models.Legislator{}, &models.LegislatorDistrictScore{}, &models.LegislatorVote{}, &models.Organization{}, &models.OrganizationBillPosition{}, &models.OrganizationBillPositionChange{}, &models.Passkey{}, &models.PushNotificationSubscription{}, &models.RefreshToken{}, &models.SwayLocale{}, &models.UserAddress{}, &models.UserDistrict{}, &models.UserInviter{}, &models.UserLegislator{}, &models.UserLegislatorEmail{}, &models.UserLegislatorScore{}, &models.UserOrganizationMembership{}, &models.UserOrganizationMembershipInvite{}, &models.UserVote{}, &models.Vote{})

	// Set up controllers
	homeController := controllers.NewHomeController(inertia)
	usersController := controllers.NewUsersController(inertia, db)
	legislatorsController := controllers.NewLegislatorsController(inertia, db)

	// Set up routes
	r.GET("/", homeController.Index)
	r.POST("/users", usersController.Create)
	r.GET("/legislators", legislatorsController.Index)
	r.GET("/legislators/:id", legislatorsController.Show)

	// Start the server
	if err := http.ListenAndServe(":8080", r); err != nil {
		log.Fatal(err)
	}
}
