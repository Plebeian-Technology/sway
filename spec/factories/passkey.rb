FactoryBot.define do
  factory :passkey do
    user
    external_id { SecureRandom.uuid }
    public_key { SecureRandom.hex }
    # @lat: [[identity-and-access#A passkey label is unique to its owner, not to the system]]
    sequence(:label) { |n| "Test Passkey #{n}" }
    sign_count { 0 }
  end
end
