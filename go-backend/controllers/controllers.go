package controllers

import (
	"github.com/romsar/gonertia/v2"
	"gorm.io/gorm"
)

// ApplicationController handles shared logic for all controllers.
type ApplicationController struct {
	Inertia *gonertia.Inertia
	DB      *gorm.DB
}

// NewApplicationController creates a new ApplicationController.
func NewApplicationController(inertia *gonertia.Inertia, db *gorm.DB) *ApplicationController {
	return &ApplicationController{Inertia: inertia, DB: db}
}


// Placeholder for other controllers
// ...
