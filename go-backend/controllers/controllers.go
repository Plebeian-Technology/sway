package controllers

import "github.com/romsar/gonertia/v2"

// ApplicationController handles shared logic for all controllers.
type ApplicationController struct {
	Inertia *gonertia.Inertia
}

// NewApplicationController creates a new ApplicationController.
func NewApplicationController(inertia *gonertia.Inertia) *ApplicationController {
	return &ApplicationController{Inertia: inertia}
}

// UsersController handles requests for users.
type UsersController struct {
	Inertia *gonertia.Inertia
}

// NewUsersController creates a new UsersController.
func NewUsersController(inertia *gonertia.Inertia) *UsersController {
	return &UsersController{Inertia: inertia}
}

// LegislatorsController handles requests for legislators.
type LegislatorsController struct {
	Inertia *gonertia.Inertia
}

// NewLegislatorsController creates a new LegislatorsController.
func NewLegislatorsController(inertia *gonertia.Inertia) *LegislatorsController {
	return &LegislatorsController{Inertia: inertia}
}

// Placeholder for other controllers
// ...
