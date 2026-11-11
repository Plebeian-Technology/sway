# frozen_string_literal: true

# @lat: [[bill-schedule-calendar-dates#Bare release dates in the bill schedule tab#Scheduler navigation, today control, and pagination]]
module BillScheduleBrowserHelpers
  AGENDA_DATE_TEST_ID_PREFIX = "btn-select-agenda-date-"

  def select_first_available_agenda_date(page)
    button =
      page.first(
        "[data-testid^='#{AGENDA_DATE_TEST_ID_PREFIX}']:not([disabled])",
        text: "Select date",
        minimum: 1
      )
    date = button["data-testid"].delete_prefix(AGENDA_DATE_TEST_ID_PREFIX)
    raise "Agenda date test id did not contain an ISO calendar day" unless Date.iso8601(date).iso8601 == date

    button.click
    date
  end
end
