# frozen_string_literal: true

class MirrorExternalAssetJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(record_class_name:, record_id:, attachment_name:, url_column:)
    record_class = record_class_name.constantize
    record = record_class.find_by(id: record_id)
    return if record.blank?

    ExternalAssetMirrorService.call(record:, attachment_name:, url_column:)
  end
end
