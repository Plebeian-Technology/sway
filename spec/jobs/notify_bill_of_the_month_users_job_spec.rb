require "rails_helper"

RSpec.describe NotifyBillOfTheMonthUsersJob, type: :job do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
  end

  describe "queueing" do
    it "enqueues on the background queue with canonical job class" do
      expect {
        NotifyBillOfTheMonthUsersJob.perform_later
      }.to have_enqueued_job(NotifyBillOfTheMonthUsersJob).on_queue("background")
    end
  end

  context "a bill already exists" do
    it "is not notifyable because the scheduled_release_date_utc has passed" do
      bill = create(:bill, scheduled_release_date_utc: 3.days.ago)
      expect(bill.notifyable?).to eql(false)
    end

    it "is not notifyable because scheduled_release_date_utc is in the future" do
      bill = create(:bill, scheduled_release_date_utc: 3.days.from_now)
      expect(bill.notifyable?).to eql(false)
    end

    it "is not notifyable because it already has a BillNotification" do
      bill = create(:bill, scheduled_release_date_utc: Time.zone.now)
      expect(bill.notifyable?).to eql(true)
      BillNotification.create!(bill:)
      expect(bill.notifyable?).to eql(false)
    end

    it "is notifyable" do
      bill = create(:bill, scheduled_release_date_utc: Time.zone.now)
      expect(bill.notifyable?).to eql(true)
    end
  end

  context "a user has a push notification subscription" do
    include_context "Setup"

    it "sends a notification when a BillNotification is created" do
      notifier =
        class_double("WebPush").as_stubbed_const(
          transfer_nested_constants: true
        )
      expect(notifier).to receive(:payload_send) # to

      sway_locale, user = setup
      PushNotificationSubscription.create!(
        endpoint: "https://push.example/taco",
        p256dh: "taco",
        auth: "taco",
        user: user,
        subscribed: true
      )

      bill = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: Time.zone.now)
      BillNotification.create!(bill:)
    end

    it "does NOT send a web push notification to a user in a different locale or with botm_announcement disabled" do
      notifier =
        class_double("WebPush").as_stubbed_const(
          transfer_nested_constants: true
        )
      expect(notifier).not_to receive(:payload_send)

      sway_locale, user = setup
      create(:notification_preference, user: user, key: "botm_announcement", enabled: false)
      PushNotificationSubscription.create!(
        endpoint: "https://push.example/disabled",
        p256dh: "taco",
        auth: "taco",
        user: user,
        subscribed: true
      )

      other_user = create(:user)
      PushNotificationSubscription.create!(
        endpoint: "https://push.example/other-locale",
        p256dh: "taco",
        auth: "taco",
        user: other_user,
        subscribed: true
      )

      bill = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: Time.zone.now)
      BillNotification.create!(bill:)
    end

    it "does NOT send a notification, when a BillNotification is NOT created" do
      notifier =
        class_double("WebPush").as_stubbed_const(
          transfer_nested_constants: true
        )
      expect(notifier).to_not receive(:payload_send) # to_not

      _sway_locale, user = setup
      PushNotificationSubscription.create!(
        endpoint: "https://push.example/taco",
        p256dh: "taco",
        auth: "taco",
        user: user,
        subscribed: true
      )

      create(:bill, scheduled_release_date_utc: Time.zone.now)
    end
  end

  context "native push fan-out" do
    include_context "Setup"

    it "enqueues SendNativePushJob per active push-enabled device for users with botm_announcement=true" do
      sway_locale, user = setup
      create(:notification_preference, user: user, key: "botm_announcement", enabled: true)
      ios_device = create(:user_device, user: user, platform: "ios", push_token: "apns-tok")
      android_device = create(:user_device, user: user, platform: "android", push_token: "fcm-tok")
      # Revoked device should be skipped.
      revoked = create(:user_device, user: user, platform: "ios", push_token: "old", revoked_at: Time.current)

      bill = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: Time.zone.now)

      expect {
        described_class.new.perform
      }.to have_enqueued_job(SendNativePushJob).at_least(2).times

      expect(SendNativePushJob).to have_been_enqueued.with(
        ios_device.id,
        hash_including(kind: "botm_announcement", title: "New Bill of the Month")
      )
      expect(SendNativePushJob).to have_been_enqueued.with(
        android_device.id,
        hash_including(kind: "botm_announcement", title: "New Bill of the Month")
      )
      expect(SendNativePushJob).not_to have_been_enqueued.with(revoked.id, anything)
      expect(BillNotification.where(bill: bill)).to exist
    end

    it "does NOT enqueue SendNativePushJob for a user whose only enabled preference row is not botm_announcement" do
      sway_locale, user = setup
      create(:notification_preference, user: user, key: "legislator_voted", enabled: true)
      create(:user_device, user: user, platform: "ios", push_token: "apns-tok")
      create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: Time.zone.now)

      expect {
        described_class.new.perform
      }.not_to have_enqueued_job(SendNativePushJob)
    end

    it "does NOT enqueue SendNativePushJob for users in a different locale" do
      _sway_locale, user = setup
      create(:notification_preference, user: user, key: "botm_announcement", enabled: true)
      device = create(:user_device, user: user, platform: "ios", push_token: "apns-tok")
      other_locale = create(:sway_locale, :congress)
      create(:bill, sway_locale: other_locale, scheduled_release_date_utc: Time.zone.now)

      expect {
        described_class.new.perform
      }.not_to have_enqueued_job(SendNativePushJob).with(device.id, anything)
    end

    it "sends a payload whose body carries the title's headline rather than the stored title" do
      sway_locale, user = setup
      create(:notification_preference, user: user, key: "botm_announcement", enabled: true)
      device = create(:user_device, user: user, platform: "ios", push_token: "apns-tok")
      bill =
        create(
          :bill,
          sway_locale: sway_locale,
          scheduled_release_date_utc: Time.zone.now,
          title: "Zoning Code – Modifications FOR the purpose of amending provisions"
        )

      described_class.new.perform

      expect(SendNativePushJob).to have_been_enqueued.with(
        device.id,
        hash_including(body: "#{bill.sway_locale.city_name}: Zoning Code")
      )
    end

    it "does NOT enqueue SendNativePushJob when user has botm_announcement disabled" do
      sway_locale, user = setup
      create(:notification_preference, user: user, key: "botm_announcement", enabled: false)
      create(:user_device, user: user, platform: "ios", push_token: "apns-tok")
      create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: Time.zone.now)

      expect { described_class.new.perform }.not_to have_enqueued_job(SendNativePushJob)
    end

    it "does NOT enqueue SendNativePushJob when no eligible bill exists" do
      _sway_locale, user = setup
      create(:notification_preference, user: user, key: "botm_announcement", enabled: true)
      create(:user_device, user: user, platform: "ios", push_token: "apns-tok")
      # No bill scheduled for today.
      expect { described_class.new.perform }.not_to have_enqueued_job(SendNativePushJob)
    end
  end

  # The schema allows one Bill of the Month per locale per day, so every locale
  # that scheduled one today has to be notified — not only the first one by id.
  context "multiple locales each with a notifyable Bill of the Month" do
    it "creates a BillNotification for EVERY locale's Bill of the Month, not just the first" do
      locale_a = create(:sway_locale)
      locale_b = create(:sway_locale)
      bill_a = create(:bill, sway_locale: locale_a, scheduled_release_date_utc: Time.zone.today)
      bill_b = create(:bill, sway_locale: locale_b, scheduled_release_date_utc: Time.zone.today)

      described_class.new.perform

      expect(BillNotification.where(bill: bill_a)).to exist
      expect(BillNotification.where(bill: bill_b)).to exist
    end

    it "keeps notifying the other locales when one bill's notification raises (per-bill rescue)" do
      locale_a = create(:sway_locale)
      locale_b = create(:sway_locale)
      bill_a = create(:bill, sway_locale: locale_a, scheduled_release_date_utc: Time.zone.today)
      bill_b = create(:bill, sway_locale: locale_b, scheduled_release_date_utc: Time.zone.today)

      # Make only bill_a's notification fail. The sweep still has to reach
      # bill_b, whatever order it works through them in.
      allow(BillNotification).to receive(:create!).and_wrap_original do |orig, attrs|
        raise "simulated notification failure" if attrs.is_a?(Hash) && attrs[:bill] == bill_a
        orig.call(attrs)
      end

      described_class.new.perform

      expect(BillNotification.where(bill: bill_a)).not_to exist
      expect(BillNotification.where(bill: bill_b)).to exist
    end
  end

  # @lat: [[bill-of-the-month-notify-job-per-locale-fix#Why the featured bill notify job iterates per locale]]
  # @lat: [[bill-of-the-month-notify-job-per-locale-fix#Web push vs native push fan-out]]
  # @lat: [[bill-of-the-month-notify-job-per-locale-fix#Why native push fan-out uses one joined query]]
  describe "concurrent race logging and recurring schedule" do
    include_context "Setup"

    it "logs botm_notify.bill_failed and continues when a concurrent worker hits RecordNotUnique" do
      locale_a = create(:sway_locale)
      locale_b = create(:sway_locale)
      bill_a = create(:bill, sway_locale: locale_a, scheduled_release_date_utc: Time.zone.today)
      bill_b = create(:bill, sway_locale: locale_b, scheduled_release_date_utc: Time.zone.today)

      allow(BillNotification).to receive(:create!).and_wrap_original do |orig, attrs|
        raise ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: bill_notifications.bill_id") if attrs.is_a?(Hash) && attrs[:bill] == bill_a
        orig.call(attrs)
      end

      expect(SwayLogging).to receive(:log_exception).with(
        "botm_notify.bill_failed",
        hash_including(bill_id: bill_a.id, sway_locale_id: locale_a.id, exception: instance_of(ActiveRecord::RecordNotUnique))
      )

      described_class.new.perform
      expect(BillNotification.where(bill: bill_b)).to exist
    end

    it "configures notify_bill_of_the_month_users_job in config/recurring.yml across development and production" do
      config = YAML.safe_load_file(Rails.root.join("config", "recurring.yml"), aliases: true)

      %w[development production].each do |env|
        entry = config.dig(env, "notify_bill_of_the_month_users_job")
        expect(entry).to include(
          "class" => "NotifyBillOfTheMonthUsersJob",
          "queue" => "background",
          "schedule" => "every day at 6pm"
        )
      end
    end
  end

  describe "feed update broadcast" do
    it "enqueues FeedUpdateBroadcastJob for users in the released bill's locale" do
      locale_a = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
      locale_b = create(:sway_locale, city: "maryland", state: "maryland", country: "united_states")

      district_a = create(:district, sway_locale: locale_a)
      district_b = create(:district, sway_locale: locale_b)

      leg_a = create(:legislator, district: district_a)
      leg_b = create(:legislator, district: district_b)

      user_in_locale = create(:user)
      create(:user_legislator, user: user_in_locale, legislator: leg_a, active: true)

      user_other_locale = create(:user)
      create(:user_legislator, user: user_other_locale, legislator: leg_b, active: true)

      create(:bill, sway_locale: locale_a, scheduled_release_date_utc: Time.zone.today)

      expect {
        described_class.new.perform
      }.to have_enqueued_job(FeedUpdateBroadcastJob).with([user_in_locale.id])
    end
  end
end
