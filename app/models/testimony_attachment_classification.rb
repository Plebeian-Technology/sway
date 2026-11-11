# frozen_string_literal: true

# @lat: [[testimony-attachment-classification-cache-key#Why only the model's answers are cached]]
# == Schema Information
#
# Table name: testimony_attachment_classifications
# Database name: primary
#
#  id              :integer          not null, primary key
#  label           :string           not null
#  model           :string
#  prompt_version  :string
#  source_endpoint :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  attachment_id   :integer          not null
#  sway_locale_id  :integer          not null
#
# Indexes
#
#  index_testimony_classifications_on_locale_and_attachment  (sway_locale_id,attachment_id) UNIQUE
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
class TestimonyAttachmentClassification < ApplicationRecord
  TESTIMONY = "testimony"
  NOT_TESTIMONY = "not_testimony"
  LABELS = [TESTIMONY, NOT_TESTIMONY].freeze

  belongs_to :sway_locale

  validates :source_endpoint, presence: true
  validates :attachment_id, presence: true, uniqueness: {scope: :sway_locale_id}
  validates :label, presence: true, inclusion: {in: LABELS}

  # @lat: [[testimony-attachment-classification-cache-key#Why source_endpoint is deliberately NOT part of the key]]
  scope :for_verdict, ->(sway_locale_id, attachment_id, model, prompt_version) {
    where(
      sway_locale_id: sway_locale_id,
      attachment_id: attachment_id,
      model: model,
      prompt_version: prompt_version
    )
  }

  # @lat: [[testimony-attachment-classification-cache-key#Three deleted members, and why they aren't coming back]]
end
