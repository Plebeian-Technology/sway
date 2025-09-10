# typed: strict

# When a Bill becomes the Bill of the Week
# Notify all users via push
class OnBillBecomesBotwNotifyUsersJob < ApplicationJob
    extend T::Sig

    queue_as :background

    sig { void }
    def perform
        SwayLocale.all.each do |sway_locale|
            botw = Bill.of_the_week(sway_locale:)

            # Only send 1 notification per iteration of this job
            break if botw&.notifyable? && BillNotification.create!(bill: botw)
        end
    end
end
