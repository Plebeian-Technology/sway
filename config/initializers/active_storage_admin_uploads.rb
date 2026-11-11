# frozen_string_literal: true

# @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule]]
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.include(AdminOnlyDirectUploads)
end
