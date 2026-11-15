# frozen_string_literal: true

# @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day]]
module PhoneVerificationSendLimit
  COOLDOWN = 1.minute
  DAILY_LIMIT = 10
  WINDOW = 24.hours

  def self.claim(phone:, store:, now: Time.current)
    key = cache_key(phone)
    now_seconds = now.to_i
    sent_at = recent_sends(store, key, now_seconds)

    daily = daily_wait(sent_at, now_seconds)
    return [daily, cooldown_wait(store, key, now_seconds)].compact.max if daily

    # @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#The cooldown is claimed in one atomic write]]
    unless store.write(cooldown_key(key), now_seconds, expires_in: COOLDOWN, unless_exist: true)
      started_at = store.read(cooldown_key(key))
      return [COOLDOWN.to_i - (now_seconds - started_at.to_i), 1].max unless started_at.nil?

      SwayLogging.warn("phone_verification_send_limit.cooldown_unreadable")
      store.write(cooldown_key(key), now_seconds, expires_in: COOLDOWN)
    end

    store.write(key, (sent_at + [now_seconds]).last(DAILY_LIMIT), expires_in: WINDOW)
    nil
  end

  # @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#A send Twilio refuses gives its daily slot back]]
  def self.release(phone:, store:, sent_at:)
    key = cache_key(phone)
    sends = Array(store.read(key)).map(&:to_i)
    index = sends.rindex(sent_at)
    return if index.nil?

    sends.delete_at(index)
    store.write(key, sends, expires_in: WINDOW)
  end

  def self.cache_key(phone)
    # @lat: [[phone-cache-hashing]]
    "rate-limit:phone_verification_send:#{PhoneCacheKey.digest(phone)}"
  end

  def self.cooldown_key(key)
    "#{key}:cooldown"
  end

  def self.recent_sends(store, key, now_seconds)
    Array(store.read(key)).map(&:to_i).select { |at| at > now_seconds - WINDOW.to_i }.sort
  end

  def self.daily_wait(sent_at, now_seconds)
    oldest = sent_at.first
    WINDOW.to_i - (now_seconds - oldest) if oldest && sent_at.size >= DAILY_LIMIT
  end

  def self.cooldown_wait(store, key, now_seconds)
    started_at = store.read(cooldown_key(key))
    return nil if started_at.nil?

    wait = COOLDOWN.to_i - (now_seconds - started_at.to_i)
    wait if wait.positive?
  end
end
