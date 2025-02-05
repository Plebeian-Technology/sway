module SeedErrors
  class MissingRegionCode < StandardError; end

  class NonStateRegionCode < StandardError; end
end
