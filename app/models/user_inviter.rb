# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: user_inviters
#
#  id          :integer          not null, primary key
#  user_id     :integer          not null
#  invite_uuid :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class UserInviter < ApplicationRecord
  extend T::Sig

  T.unsafe(self).has_shortened_urls

  INVITE_URL_BASE = "/invites/%<user_id>s/%<uuid>s"
  INVITED_BY_SESSION_KEY = :invited_by_id

  belongs_to :user

  before_create do
    self.invite_uuid = SecureRandom.uuid
  end

  after_commit :shorten_url

  class << self
    extend T::Sig

    sig { params(user: User).void }
    def from(user:)
      UserInviter.create!(user:)
    end
  end

  sig { returns(User) }
  def user
    T.cast(super, User)
  end

  def short_url
    shortened_urls.first&.url
  end

  private

  def shorten_url
    Shortener::ShortenedUrl.generate(invite_url, owner: self)
  end

  sig { returns(String) }
  def invite_url
    format(INVITE_URL_BASE, uuid: invite_uuid, user_id: user.id)
  end
end
