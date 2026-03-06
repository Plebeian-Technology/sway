class String
  def remove_non_digits
    tr("^0-9", "")
  end

  def remove_non_alpha
    tr("^[a-zA-Z]", "")
  end

  def remove_non_alpha_numeric
    tr("^[a-zA-Z0-9]", "")
  end

  def is_numeric?
    scan(/\D/).empty?
  end
end

module RGeo
  module GeoJSON
    class Feature
      def district
        area = properties.fetch("area_name")
        area.is_a?(String) ? area.remove_non_digits.to_i : area
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
