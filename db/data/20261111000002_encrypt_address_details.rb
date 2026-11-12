# frozen_string_literal: true

# @lat: [[personal-detail-encryption#Converting the rows that already exist]]
class EncryptAddressDetails < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationAddress < ActiveRecord::Base
    self.table_name = "addresses"

    encrypts :street
    encrypts :street2
    encrypts :street3
    encrypts :latitude
    encrypts :longitude
  end

  def up
    MigrationAddress.reset_column_information

    stats = Hash.new(0)

    MigrationAddress.find_each do |address|
      if MigrationAddress.encrypted_attributes.all? { |name|
        address.read_attribute(name).nil? || address.encrypted_attribute?(name)
      }
        stats[:already_encrypted] += 1
        next
      end

      address.encrypt
      stats[:encrypted] += 1
    end

    SwayLogging.info("encrypt_address_details - stats=#{stats}")
    say "encrypted #{stats[:encrypted]}, already encrypted #{stats[:already_encrypted]}."
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
