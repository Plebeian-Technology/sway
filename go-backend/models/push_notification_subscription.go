package models

import "gorm.io/gorm"

// PushNotificationSubscription model
type PushNotificationSubscription struct {
	gorm.Model
	UserID     uint
	Endpoint   string
	P256dh     string
	Auth       string
}
