shared_context "TwilioDouble" do
  let(:twilio_verification_status) { "approved" }
  let(:twilio_client_double) { instance_double(Twilio::REST::Client) }
  let(:twilio_verify_double) { instance_double("TwilioVerify") }
  let(:twilio_verify_v2_double) { instance_double("TwilioVerifyV2") }
  let(:twilio_service_double) { instance_double("TwilioVerifyService") }
  let(:twilio_verifications_double) { instance_double("TwilioVerifications") }
  let(:twilio_verification_checks_double) do
    instance_double("TwilioVerificationChecks")
  end
  let(:twilio_verification_result) do
    instance_double(
      "TwilioVerificationResult",
      status: twilio_verification_status,
    )
  end

  before do
    allow(Twilio::REST::Client).to receive(:new).and_return(
      twilio_client_double,
    )
    allow(twilio_client_double).to receive(:verify).and_return(
      twilio_verify_double,
    )
    allow(twilio_verify_double).to receive(:v2).and_return(
      twilio_verify_v2_double,
    )
    allow(twilio_verify_v2_double).to receive(:services).and_return(
      twilio_service_double,
    )
    allow(twilio_service_double).to receive(:verifications).and_return(
      twilio_verifications_double,
    )
    allow(twilio_service_double).to receive(:verification_checks).and_return(
      twilio_verification_checks_double,
    )

    allow(twilio_verifications_double).to receive(:create).and_return(
      instance_double("TwilioVerification", sid: "VE123"),
    )
    allow(twilio_verification_checks_double).to receive(:create).and_return(
      twilio_verification_result,
    )
  end
end
