package notifications

import (
	"sway-go/models"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

type MockNotificationService struct {
	SentSMS []struct {
		To   string
		Body string
	}
}

func (m *MockNotificationService) SendSMS(to string, body string) error {
	m.SentSMS = append(m.SentSMS, struct {
		To   string
		Body string
	}{To: to, Body: body})
	return nil
}

func setupTestDB() *gorm.DB {
	db, err := gorm.Open(sqlite.Open("file::memory:"), &gorm.Config{})
	if err != nil {
		panic(err)
	}
	// Migrate schema
	err = db.AutoMigrate(
		&models.User{},
		&models.SwayLocale{},
		&models.District{},
		&models.UserDistrict{},
		&models.Bill{},
		&models.BillNotification{},
		&models.UserVote{},
		&models.UserBillReminder{},
	)
	if err != nil {
		panic(err)
	}
	return db
}

func TestCheckBillOfTheWeek(t *testing.T) {
	db := setupTestDB()
	mockNotifier := &MockNotificationService{}
	worker := NewWorker(db, mockNotifier)

	// Create Locale, District
	locale := models.SwayLocale{City: "Test City", State: "TS", Country: "Test Country"}
	db.Create(&locale)
	district := models.District{Name: "District 1", SwayLocaleID: locale.ID}
	db.Create(&district)

	// Create User (Opted-in)
	phone := "+1234567890"
	user := models.User{
		Phone:                   &phone,
		IsPhoneVerified:         true,
		SmsNotificationsEnabled: true,
	}
	db.Create(&user)
	db.Create(&models.UserDistrict{UserID: user.ID, DistrictID: district.ID})

	// Create User (Opted-out)
	phone2 := "+1987654321"
	user2 := models.User{
		Phone:                   &phone2,
		IsPhoneVerified:         true,
		SmsNotificationsEnabled: false,
	}
	db.Create(&user2)
	db.Create(&models.UserDistrict{UserID: user2.ID, DistrictID: district.ID})

	// Create Bill scheduled for Today
	today := time.Now().UTC()
	bill := models.Bill{
		Title:                   "Test Bill",
		SwayLocaleID:            locale.ID,
		ScheduledReleaseDateUTC: &today,
	}
	db.Create(&bill)

	// Run Check
	err := worker.CheckBillOfTheWeek()
	assert.NoError(t, err)

	// Verify User 1 got SMS
	assert.Equal(t, 1, len(mockNotifier.SentSMS))
	assert.Equal(t, phone, mockNotifier.SentSMS[0].To)
	assert.Contains(t, mockNotifier.SentSMS[0].Body, "New Bill of the Week")

	// Verify BillNotification created
	var notif models.BillNotification
	err = db.Where("bill_id = ?", bill.ID).First(&notif).Error
	assert.NoError(t, err)

	// Run Check again - should send no new SMS
	mockNotifier.SentSMS = nil // Reset
	err = worker.CheckBillOfTheWeek()
	assert.NoError(t, err)
	assert.Equal(t, 0, len(mockNotifier.SentSMS))
}

func TestCheckVotingReminders(t *testing.T) {
	db := setupTestDB()
	mockNotifier := &MockNotificationService{}
	worker := NewWorker(db, mockNotifier)

	// Create Locale, District
	locale := models.SwayLocale{City: "Test City", State: "TS", Country: "Test Country"}
	db.Create(&locale)
	district := models.District{Name: "District 1", SwayLocaleID: locale.ID}
	db.Create(&district)

	// Create Bill scheduled 5 days ago
	fiveDaysAgo := time.Now().UTC().AddDate(0, 0, -5)
	bill := models.Bill{
		Title:                   "Old Bill",
		SwayLocaleID:            locale.ID,
		ScheduledReleaseDateUTC: &fiveDaysAgo,
	}
	db.Create(&bill)

	// User 1: Has not voted, Opted-in
	phone1 := "+1111111111"
	user1 := models.User{Phone: &phone1, IsPhoneVerified: true, SmsNotificationsEnabled: true}
	db.Create(&user1)
	db.Create(&models.UserDistrict{UserID: user1.ID, DistrictID: district.ID})

	// User 2: Has voted, Opted-in
	phone2 := "+2222222222"
	user2 := models.User{Phone: &phone2, IsPhoneVerified: true, SmsNotificationsEnabled: true}
	db.Create(&user2)
	db.Create(&models.UserDistrict{UserID: user2.ID, DistrictID: district.ID})
	db.Create(&models.UserVote{UserID: user2.ID, BillID: bill.ID, Support: "yes"})

	// User 3: Not voted, Opted-out
	phone3 := "+3333333333"
	user3 := models.User{Phone: &phone3, IsPhoneVerified: true, SmsNotificationsEnabled: false}
	db.Create(&user3)
	db.Create(&models.UserDistrict{UserID: user3.ID, DistrictID: district.ID})

	// Run Check
	err := worker.CheckVotingReminders()
	assert.NoError(t, err)

	// Verify only User 1 got SMS
	assert.Equal(t, 1, len(mockNotifier.SentSMS))
	assert.Equal(t, phone1, mockNotifier.SentSMS[0].To)
	assert.Contains(t, mockNotifier.SentSMS[0].Body, "Reminder")

	// Verify UserBillReminder created for User 1
	var reminder models.UserBillReminder
	err = db.Where("user_id = ? AND bill_id = ?", user1.ID, bill.ID).First(&reminder).Error
	assert.NoError(t, err)

	// Run Check again - should send no new SMS (already reminded)
	mockNotifier.SentSMS = nil
	err = worker.CheckVotingReminders()
	assert.NoError(t, err)
	assert.Equal(t, 0, len(mockNotifier.SentSMS))
}
