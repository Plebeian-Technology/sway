# frozen_string_literal: true

# @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#Adding a passkey re-verifies by SMS first]]
class AddAaguidToPasskeys < ActiveRecord::Migration[8.1]
  def change
    add_column :passkeys, :aaguid, :string
  end
end
