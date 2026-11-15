# frozen_string_literal: true

# @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day]]
RSpec.shared_examples "a code send limited per phone" do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    with_app_config(:dev_login, skip_phone_verification: false) { example.run }
  end

  it "refuses a second send from the same IP within a minute with the remaining wait and no Twilio call" do
    with_rate_limit_enabled(:phone_verify) do
      freeze_time do
        code_send_request(ip: "10.9.0.1")
        expect(response).to have_http_status(code_send_status)

        travel 18.seconds
        code_send_request(ip: "10.9.0.1")

        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers["Retry-After"]).to eq("42")
        expect(twilio_verifications_double).to have_received(:create).once
      end
    end
  end

  it "refuses the same phone from another IP within the minute with the remaining wait and no Twilio call" do
    with_rate_limit_enabled(:phone_verify) do
      freeze_time do
        code_send_request(ip: "10.9.0.1")
        travel 5.seconds
        code_send_request(ip: "10.9.0.2")

        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers["Retry-After"]).to eq("55")
        expect(twilio_verifications_double).to have_received(:create).once
      end
    end
  end

  it "refuses the 11th send in 24 hours from another IP until the oldest send is a day old" do
    with_rate_limit_enabled(:phone_verify) do
      freeze_time do
        10.times do |i|
          code_send_request(ip: "10.9.0.#{i + 1}")
          expect(response).to have_http_status(code_send_status)
          travel 25.minutes
        end

        code_send_request(ip: "10.9.0.99")

        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers["Retry-After"]).to eq((24.hours - 250.minutes).to_i.to_s)
        expect(twilio_verifications_double).to have_received(:create).exactly(10).times
      end
    end
  end

  it "sends again from the same IP once the minute has passed" do
    with_rate_limit_enabled(:phone_verify) do
      freeze_time do
        code_send_request(ip: "10.9.0.1")
        travel 60.seconds
        code_send_request(ip: "10.9.0.1")

        expect(response).to have_http_status(code_send_status)
        expect(twilio_verifications_double).to have_received(:create).twice
      end
    end
  end

  it "keeps the one-minute wait after a send Twilio refuses" do
    allow(twilio_verifications_double).to receive(:create).and_raise(Twilio::REST::TwilioError, "connection refused")

    with_rate_limit_enabled(:phone_verify) do
      freeze_time do
        code_send_request(ip: "10.9.0.1")
        expect(response).not_to have_http_status(:too_many_requests)

        travel 18.seconds
        code_send_request(ip: "10.9.0.1")

        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers["Retry-After"]).to eq("42")
        expect(twilio_verifications_double).to have_received(:create).once
      end
    end
  end

  it "answers Twilio's refusal of a sixth send in one verification with a ten-minute wait and gives the daily slot back" do
    twilio_error = Twilio::REST::RestError.allocate
    allow(twilio_error).to receive_messages(code: 60_203, status_code: 429, full_message: "Max send attempts reached")
    allow(twilio_verifications_double).to receive(:create).and_raise(twilio_error)
    allow(PhoneVerificationSendLimit).to receive(:release).and_call_original

    with_rate_limit_enabled(:phone_verify) do
      freeze_time do
        code_send_request(ip: "10.9.0.1")

        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers["Retry-After"]).to eq("600")
        expect(PhoneVerificationSendLimit).to have_received(:release).with(hash_including(sent_at: Time.current.to_i)).once
      end
    end
  end

  it "gives a send Twilio refuses its daily slot back" do
    attempts = 0
    allow(twilio_verifications_double).to receive(:create) do
      attempts += 1
      raise Twilio::REST::TwilioError, "connection refused" if attempts <= 10

      instance_double("TwilioVerification", sid: "VE123")
    end

    with_rate_limit_enabled(:phone_verify) do
      freeze_time do
        10.times do
          code_send_request(ip: "10.9.0.1")
          expect(response).not_to have_http_status(:too_many_requests)
          travel 25.minutes
        end

        code_send_request(ip: "10.9.0.1")

        expect(response).to have_http_status(code_send_status)
        expect(twilio_verifications_double).to have_received(:create).exactly(11).times
      end
    end
  end

  it "refuses the 11th send in 24 hours until the oldest send is a day old" do
    with_rate_limit_enabled(:phone_verify) do
      freeze_time do
        first_sent_at = Time.current
        10.times do
          code_send_request(ip: "10.9.0.1")
          expect(response).to have_http_status(code_send_status)
          travel 25.minutes
        end

        code_send_request(ip: "10.9.0.1")

        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers["Retry-After"]).to eq((24.hours - 250.minutes).to_i.to_s)
        expect(twilio_verifications_double).to have_received(:create).exactly(10).times

        travel_to first_sent_at + 24.hours + 1.second
        code_send_request(ip: "10.9.0.1")

        expect(response).to have_http_status(code_send_status)
        expect(twilio_verifications_double).to have_received(:create).exactly(11).times
      end
    end
  end
end
