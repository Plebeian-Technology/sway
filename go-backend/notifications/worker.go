package notifications

import (
	"fmt"
	"log"
	"sway-go/models"
	"time"

	"gorm.io/gorm"
)

type Worker struct {
	DB       *gorm.DB
	Notifier NotificationService
}

func NewWorker(db *gorm.DB, notifier NotificationService) *Worker {
	return &Worker{
		DB:       db,
		Notifier: notifier,
	}
}

func (w *Worker) RunChecks() {
	log.Println("Running notification checks...")
	if err := w.CheckBillOfTheWeek(); err != nil {
		log.Printf("Error checking bill of the week: %v", err)
	}
	if err := w.CheckVotingReminders(); err != nil {
		log.Printf("Error checking voting reminders: %v", err)
	}
}

func (w *Worker) CheckBillOfTheWeek() error {
	todayStart := time.Now().UTC().Truncate(24 * time.Hour)
	tomorrowStart := todayStart.Add(24 * time.Hour)

	// Find bills scheduled for today that haven't been notified
	var bills []models.Bill
	err := w.DB.Joins("LEFT JOIN bill_notifications ON bill_notifications.bill_id = bills.id").
		Where("scheduled_release_date_utc >= ? AND scheduled_release_date_utc < ? AND bill_notifications.id IS NULL", todayStart, tomorrowStart).
		Preload("SwayLocale").
		Find(&bills).Error

	if err != nil {
		return err
	}

	for _, bill := range bills {
		log.Printf("Processing Bill of the Week notification for Bill ID: %d", bill.ID)

		users, err := w.getUsersForLocale(bill.SwayLocaleID)
		if err != nil {
			log.Printf("Error getting users for locale %d: %v", bill.SwayLocaleID, err)
			continue
		}

		message := fmt.Sprintf("New Bill of the Week in %s: %s. Check it out on Sway!", bill.SwayLocale.City, bill.Title)

		for _, user := range users {
			if user.Phone != nil {
				if err := w.Notifier.SendSMS(*user.Phone, message); err != nil {
					log.Printf("Failed to send SMS to %s: %v", *user.Phone, err)
				}
			}
		}

		// Mark as notified
		notif := models.BillNotification{
			BillID: bill.ID,
		}
		if err := w.DB.Create(&notif).Error; err != nil {
			log.Printf("Failed to create BillNotification for Bill %d: %v", bill.ID, err)
		}
	}

	return nil
}

func (w *Worker) CheckVotingReminders() error {
	todayStart := time.Now().UTC().Truncate(24 * time.Hour)
	fiveDaysAgoStart := todayStart.AddDate(0, 0, -5)
	fourDaysAgoStart := todayStart.AddDate(0, 0, -4)

	// Find bills that became active 5 days ago
	var bills []models.Bill
	err := w.DB.Where("scheduled_release_date_utc >= ? AND scheduled_release_date_utc < ?", fiveDaysAgoStart, fourDaysAgoStart).
		Preload("SwayLocale").
		Find(&bills).Error

	if err != nil {
		return err
	}

	for _, bill := range bills {
		log.Printf("Processing voting reminders for Bill ID: %d", bill.ID)

		users, err := w.getUsersForLocale(bill.SwayLocaleID)
		if err != nil {
			log.Printf("Error getting users for locale %d: %v", bill.SwayLocaleID, err)
			continue
		}

		for _, user := range users {
			// Check if user voted
			var voteCount int64
			w.DB.Model(&models.UserVote{}).Where("user_id = ? AND bill_id = ?", user.ID, bill.ID).Count(&voteCount)
			if voteCount > 0 {
				continue // User already voted
			}

			// Check if already reminded
			var reminderCount int64
			w.DB.Model(&models.UserBillReminder{}).Where("user_id = ? AND bill_id = ?", user.ID, bill.ID).Count(&reminderCount)
			if reminderCount > 0 {
				continue // Already reminded
			}

			// Send Reminder
			message := fmt.Sprintf("Reminder: You haven't voted on the Bill of the Week in %s: %s. Vote now on Sway!", bill.SwayLocale.City, bill.Title)
			if user.Phone != nil {
				if err := w.Notifier.SendSMS(*user.Phone, message); err != nil {
					log.Printf("Failed to send SMS to %s: %v", *user.Phone, err)
				} else {
					// Mark as reminded
					reminder := models.UserBillReminder{
						UserID: user.ID,
						BillID: bill.ID,
						SentAt: time.Now(),
					}
					if err := w.DB.Create(&reminder).Error; err != nil {
						log.Printf("Failed to create UserBillReminder for User %d Bill %d: %v", user.ID, bill.ID, err)
					}
				}
			}
		}
	}
	return nil
}

func (w *Worker) getUsersForLocale(localeID uint) ([]models.User, error) {
	var users []models.User
	// Assuming users are linked to districts which are linked to sway_locales
	// We only want users who opted in and have verified phone
	err := w.DB.Distinct("users.*").
		Joins("JOIN user_districts ON user_districts.user_id = users.id").
		Joins("JOIN districts ON districts.id = user_districts.district_id").
		Where("districts.sway_locale_id = ? AND users.sms_notifications_enabled = ? AND users.is_phone_verified = ?", localeID, true, true).
		Find(&users).Error
	return users, err
}
