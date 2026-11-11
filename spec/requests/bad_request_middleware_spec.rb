# frozen_string_literal: true

require "rails_helper"

# @lat: [[bad-request-responses#Rack's own bad-request family answers 400]]
RSpec.describe "malformed requests", type: :request do
  it "answers 400 when a multipart body never carries the boundary its header declares" do
    boundary = "----SwayBoundaryThatIsNeverSent"
    body = "x" * (17 * 1024)

    post "/",
      params: body,
      headers: {
        "CONTENT_TYPE" => "multipart/form-data; boundary=#{boundary}",
        "CONTENT_LENGTH" => body.bytesize.to_s
      }

    expect(response).to have_http_status(:bad_request)
    expect(response.body).to eq("Bad Request\n")
  end

  # RFC 1521 caps a multipart boundary at 70 characters and rack refuses a longer one.
  it "answers 400 for a multipart boundary longer than rack accepts" do
    body = "--#{"z" * 80}--\r\n"

    post "/",
      params: body,
      headers: {
        "CONTENT_TYPE" => "multipart/form-data; boundary=#{"z" * 80}",
        "CONTENT_LENGTH" => body.bytesize.to_s
      }

    expect(response).to have_http_status(:bad_request)
  end

  it "logs the path and the error class rather than dropping the rejection" do
    allow(SwayLogging).to receive(:warn)
    boundary = "----SwayBoundaryThatIsNeverSent"
    body = "x" * (17 * 1024)

    post "/legislators",
      params: body,
      headers: {
        "CONTENT_TYPE" => "multipart/form-data; boundary=#{boundary}",
        "CONTENT_LENGTH" => body.bytesize.to_s
      }

    expect(SwayLogging).to have_received(:warn).with(
      "bad_request.rejected",
      hash_including(request_path: "/legislators")
    )
  end
end
