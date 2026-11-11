namespace :sway do
  namespace :addresses do
    # @lat: [[personal-detail-encryption#Converting the rows that already exist]]
    desc "Encrypt street, street2 and street3 on existing address rows"
    task encrypt_streets: :environment do
      batch_size = Integer(ENV["ENCRYPT_BATCH_SIZE"] || 100)
      stats = {encrypted: 0, already_encrypted: 0, failed: 0}

      Address.find_each(batch_size:) do |address|
        if Address.encrypted_attributes.all? { |name|
          address.read_attribute(name).nil? || address.encrypted_attribute?(name)
        }
          stats[:already_encrypted] += 1
          next
        end

        address.encrypt
        stats[:encrypted] += 1
      rescue => e
        stats[:failed] += 1
        SwayLogging.error("encrypt_streets - address #{address.id} failed: #{e.class}: #{e.message}")
      end

      SwayLogging.info("encrypt_streets - stats=#{stats}")
      puts "sway:addresses:encrypt_streets - encrypted #{stats[:encrypted]}, " \
        "already encrypted #{stats[:already_encrypted]}, failed #{stats[:failed]}."
    end
  end
end
