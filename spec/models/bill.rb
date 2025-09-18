# typed: true
# frozen_string_literal: true

RSpec.describe Bill do
  context "an instance of Bill" do
    # Testing active record callbacks https://stackoverflow.com/a/16678194/6410635
    it "sends a web push notification when a Bill is created" do
      bill = build(:bill)
      expect(bill).to receive(:send_notifications)
      bill.save
    end

    it "has a downcased status after save" do
      bill = build(:bill, status: Bill::Status::PASSED.upcase)
      bill.save
      expect(bill.status).to eql(Bill::Status::PASSED.downcase)
    end
  end

  context "querying the bill of the week" do
    it "is the bill of the week" do
      bill = create(:bill)
      bill_2 = create(:bill)
      expect(bill_2.sway_locale).to eql(bill.sway_locale)
      expect(Bill.of_the_week(sway_locale: bill_2.sway_locale)).to_not eql(bill)
      expect(Bill.of_the_week(sway_locale: bill_2.sway_locale)).to eql(bill_2)
    end
  end

  context "the sway locale related to bill has a current_session_start_date after now / in the future" do
    it "is not active" do
      bill =
        build(
          :bill,
          sway_locale:
            build(
              :sway_locale,
              current_session_start_date: Time.zone.today + 1.year,
            ),
        )
      expect(bill.active).to be(false)
    end
  end

  context "the sway locale related to bill has a current_session_start_date before now / in the past" do
    it "is active" do
      bill =
        build(
          :bill,
          sway_locale:
            build(
              :sway_locale,
              current_session_start_date: Time.zone.today - 1.year,
            ),
        )
      expect(bill.active).to be(true)
    end
  end
end
