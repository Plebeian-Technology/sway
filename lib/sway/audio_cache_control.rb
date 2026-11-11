# frozen_string_literal: true

module Sway
  # @lat: [[sway-google-cloud-storage#What the bucket says about caching audio]]
  class AudioCacheControl
    Result = Data.define(:examined, :already_set, :names)

    AUDIO_EXTENSIONS = %w[.mp3 .m4a .aac .ogg .oga .opus .wav .flac .weba].freeze

    def initialize(bucket, value: SwayGoogleCloudStorage::AUDIO_CACHE_CONTROL)
      @bucket = bucket
      @value = value
    end

    def call(apply: false)
      examined = 0
      already_set = 0
      names = []

      @bucket.files.all do |file|
        next unless audio?(file)

        examined += 1
        if file.cache_control == @value
          already_set += 1
          next
        end

        names << file.name
        file.cache_control = @value if apply
      end

      Result.new(examined: examined, already_set: already_set, names: names)
    end

    private

    def audio?(file)
      file.content_type.to_s.start_with?("audio/") ||
        AUDIO_EXTENSIONS.include?(File.extname(file.name.to_s).downcase)
    end
  end
end
