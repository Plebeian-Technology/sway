# typed: true

class Set
  module SubclassCompatible
    module ClassMethods; end
  end
end

module SolidQueue
  class Execution < ::SolidQueue::Record
    module GeneratedAssociationMethods; end
  end
end
