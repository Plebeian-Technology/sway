# frozen_string_literal: true

# @lat: [[outbound-email#Outbound email#A trailing newline reads as a revoked key]]
Resend.api_key = ENV["RESEND_EMAIL_API_KEY"].to_s.strip.presence
