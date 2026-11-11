# frozen_string_literal: true

# @lat: [[sway-google-cloud-storage#What the bucket says about caching audio]]
namespace :sway do
  namespace :assets do
    desc "Write the audio caching instruction onto existing audio objects (reports only; sway:assets:audio_cache_control[apply] writes)"
    task :audio_cache_control, [:mode] => :environment do |_task, args|
      apply = args[:mode].to_s == "apply"
      bucket = SwayGoogleCloudStorage.storage.bucket(
        SwayGoogleCloudStorage::BUCKETS[:ASSETS],
        skip_lookup: true
      )

      result = Sway::AudioCacheControl.new(bucket).call(apply: apply)

      puts "[sway:assets:audio_cache_control] #{result.examined} audio objects, " \
           "#{result.already_set} already carrying #{SwayGoogleCloudStorage::AUDIO_CACHE_CONTROL}"
      result.names.each { |name| puts "  #{apply ? "set" : "would set"}: #{name}" }
    end
  end
end
