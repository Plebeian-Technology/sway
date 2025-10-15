package jobs

import (
	"fmt"
	"sway-go/models"
)

// OnBillBecomesBotwNotifyUsersJob simulates the equivalent Ruby job.
// It iterates through all SwayLocales, finds the "Bill of the Week" for each,
// and if it's notifyable, creates a BillNotification and then stops.
func OnBillBecomesBotwNotifyUsersJob() {
	locales, err := models.GetAllSwayLocales()
	if err != nil {
		fmt.Println("Error getting SwayLocales:", err)
		return
	}

	for _, locale := range locales {
		botw, err := models.GetBillOfTheWeek(locale)
		if err != nil {
			fmt.Printf("Error getting Bill of the Week for locale %s: %v\n", locale.Name, err)
			continue
		}

		if botw != nil && botw.IsNotifyable() {
			if err := models.CreateBillNotification(botw); err != nil {
				fmt.Printf("Error creating BillNotification for bill %d: %v\n", botw.ID, err)
			}
			// Only send 1 notification per iteration of this job
			break
		}
	}
}
