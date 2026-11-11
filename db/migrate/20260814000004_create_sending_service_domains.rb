# frozen_string_literal: true

# Phase 67 D-11/D-12: the learned set of sending-service domains, updated by
# the clean-testimony stage as each bill is processed, carrying the counts
# that justified each label so an operator can see why a domain was called
# a service rather than trust a number nobody can inspect.
#
# D-13: a domain is ORIGIN, never IDENTITY or STANCE — two campaigns can
# share one sending service on one bill and argue opposite positions. This
# table never records which campaign a letter belongs to or what it argues,
# only where it technically came from.
class CreateSendingServiceDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :sending_service_domains do |t|
      t.string :domain, null: false

      # SendingServiceDomain::LABELS — none/proposed/confirmed (D-12). A
      # fresh domain reads as unlabeled, never as an error.
      t.string :label, null: false, default: "none"

      t.references :confirmed_by, null: true, foreign_key: {to_table: :users}
      t.datetime :confirmed_at

      t.timestamps
    end

    add_index :sending_service_domains, :domain, unique: true

    create_table :sending_service_domain_bills do |t|
      t.references :sending_service_domain, null: false, foreign_key: true, index: false
      t.references :bill, null: false, foreign_key: true

      # THE DOMAIN ROW HOLDS NO RUNNING TOTALS OF ITS OWN. These three counts
      # are what SendingServiceDomain sums to answer "how many senders,
      # letters and machine-sent letters". Re-running the cleaning stage on
      # THIS bill replaces this row rather than adding a second — the
      # unique index below is what makes that a real guarantee — so an
      # operator tuning a rule and re-running the stage many times can never
      # inflate a domain's totals (Pitfall 12, 67-RESEARCH.md).
      t.integer :sender_count, null: false
      t.integer :letter_count, null: false

      # A letter counts as machine-sent when its text is reused by other
      # letters on the SAME bill. This is about where a letter came from,
      # never what it argues or which campaign sent it (D-13).
      t.integer :machine_sent_letter_count, null: false

      t.timestamps
    end

    add_index :sending_service_domain_bills,
      %i[sending_service_domain_id bill_id],
      unique: true,
      name: "index_sending_service_domain_bills_on_domain_and_bill"
  end
end
