# frozen_string_literal: true

# @lat: [[personal-detail-encryption#Converting the rows that already exist]]
class EncryptUserPersonalDetails < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"

    encrypts :full_name
    encrypts :email, deterministic: true
    # @lat: [[personal-detail-encryption#Why the phone number takes the weaker mode]]
    encrypts :phone, deterministic: true
    encrypts :current_sign_in_ip
    encrypts :last_sign_in_ip
  end

  def up
    MigrationUser.reset_column_information

    stats = Hash.new(0)

    MigrationUser.find_each do |user|
      if MigrationUser.encrypted_attributes.all? { |name|
        user.read_attribute(name).nil? || user.encrypted_attribute?(name)
      }
        stats[:already_encrypted] += 1
        next
      end

      user.encrypt
      stats[:encrypted] += 1
    end

    SwayLogging.info("encrypt_user_personal_details - stats=#{stats}")
    say "encrypted #{stats[:encrypted]}, already encrypted #{stats[:already_encrypted]}."
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
