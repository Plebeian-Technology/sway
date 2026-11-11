module SeedErrors
  class MissingRegionCode < StandardError
  end

  class NonStateRegionCode < StandardError
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Identity is a table of rows, not one column]]
  class UnknownIdentityScheme < StandardError
  end
end
