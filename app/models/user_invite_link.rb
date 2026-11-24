# frozen_string_literal: true

# == Schema Information
#
# Table name: user_invite_links
# Database name: primary
#
#  id          :integer          not null, primary key
#  invite_uuid :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :integer          not null
#
# Indexes
#
#  index_user_invite_links_on_invite_uuid  (invite_uuid) UNIQUE
#  index_user_invite_links_on_user_id      (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class UserInviteLink < ApplicationRecord
  has_shortened_urls
  has_many :shortened_urls, class_name: "::Shortener::ShortenedUrl", as: :owner, dependent: :destroy

  SHORT_URL_BASE = "/s/%<unique_key>s"
  INVITE_URL_BASE = "/invite/%<user_id>s/%<uuid>s"
  INVITED_BY_SESSION_KEY = :invited_by_id

  belongs_to :user

  before_create { self.invite_uuid = SecureRandom.uuid }

  after_commit :shorten_url, on: :create

  class << self
    def from(user:)
      create!(user:)
    end

    # Returns the id of the user whose invite link the attribution key names, or nil.
    # @lat: [[identity-and-access#The app names its inviter with an attribution key]]
    def inviter_id_for(attribution_key)
      return nil unless attribution_key.is_a?(String)

      kind, value = attribution_key.split(":", 2)
      return nil if value.blank?

      case kind
      when "invite" then find_by(invite_uuid: value)&.user_id
      when "s" then joins(:shortened_urls).find_by(shortened_urls: {unique_key: value})&.user_id
      end
    end
  end

  def short_url
    format(SHORT_URL_BASE, unique_key: shortened_urls.first&.unique_key)
  end

  private

  def shorten_url
    Shortener::ShortenedUrl.generate(invite_url, owner: self)
  end

  def invite_url
    format(INVITE_URL_BASE, uuid: invite_uuid, user_id: user.id)
  end
end
