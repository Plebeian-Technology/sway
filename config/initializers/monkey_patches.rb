# typed: true

class String
  extend T::Sig

  sig { returns(String) }
  def remove_non_digits
    tr('^0-9', '')
  end
end

module RGeo
  module GeoJSON
    class Feature
      extend T::Sig

      sig { returns(T.nilable(Integer)) }
      def district
        area = T.let(properties.fetch('area_name'), T.nilable(T.any(String, Integer)))
        if area&.is_a?(String)
          area.remove_non_digits.to_i
        else
          area
        end
      end
    end
  end
end

# module SwayString
#   refine String do
#     def remove_non_digits
#       tr('^0-9', '')
#     end
#   end
# end

# String.include(SwayString)
