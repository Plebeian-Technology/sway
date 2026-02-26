shared_context "TwilioDouble" do
  let(:twilio_verification_status) { "approved" }
  let(:twilio_verification_result) do
    instance_double("TwilioVerificationResult", status: twilio_verification_status)
  end

  before do
    twilio_client = instance_double(Twilio::REST::Client)
    verify_double = instance_double("TwilioVerify")
    verify_v2_double = instance_double("TwilioVerifyV2")
    service_double = instance_double("TwilioVerifyService")
    verifications_double = instance_double("TwilioVerifications")
    verification_checks_double = instance_double("TwilioVerificationChecks")

    allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client)
    allow(twilio_client).to receive(:verify).and_return(verify_double)
    allow(verify_double).to receive(:v2).and_return(verify_v2_double)
    allow(verify_v2_double).to receive(:services).and_return(service_double)
    allow(service_double).to receive(:verifications).and_return(verifications_double)
    allow(service_double).to receive(:verification_checks).and_return(verification_checks_double)

    allow(verifications_double).to receive(:create).and_return(
      instance_double("TwilioVerification", sid: "VE123"),
    )
    allow(verification_checks_double).to receive(:create).and_return(
      twilio_verification_result,
    )
  end
end
