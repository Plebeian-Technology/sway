# frozen_string_literal: true

# @lat: [[inbound-sms#Inbound SMS#Keyword messages are not forwarded]]
module SmsKeywords
  # @lat: [[inbound-sms#Inbound SMS#The keyword sets are pinned to the registered campaign]]
  STOP = %w[STOP STOPALL UNSUBSCRIBE CANCEL END QUIT OPTOUT REVOKE].freeze
  START = %w[START YES UNSTOP SUBSCRIBE].freeze
  HELP = %w[HELP INFO].freeze

  ALL = (STOP + START + HELP).freeze

  def self.normalize(body)
    body.to_s.strip.upcase
  end

  def self.keyword?(body)
    ALL.include?(normalize(body))
  end
end
