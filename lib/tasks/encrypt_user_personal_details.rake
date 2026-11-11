namespace :sway do
  namespace :users do
    # @lat: [[personal-detail-encryption#Converting the rows that already exist]]
    desc "Encrypt full_name and both sign-in internet addresses on existing user rows"
    task encrypt_personal_details: :environment do
      batch_size = Integer(ENV["ENCRYPT_BATCH_SIZE"] || 100)
      stats = {encrypted: 0, already_encrypted: 0, failed: 0}

      User.find_each(batch_size:) do |user|
        if User.encrypted_attributes.all? { |name|
          user.read_attribute(name).nil? || user.encrypted_attribute?(name)
        }
          stats[:already_encrypted] += 1
          next
        end

        user.encrypt
        stats[:encrypted] += 1
      rescue => e
        stats[:failed] += 1
        SwayLogging.error("encrypt_personal_details - user #{user.id} failed: #{e.class}: #{e.message}")
      end

      SwayLogging.info("encrypt_personal_details - stats=#{stats}")
      puts "sway:users:encrypt_personal_details - encrypted #{stats[:encrypted]}, " \
        "already encrypted #{stats[:already_encrypted]}, failed #{stats[:failed]}."
    end
  end
end
