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

  def normalize_phone
    digits = remove_non_digits
    return digits[1..] if digits.length == 11 && digits.start_with?("1")

    digits
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
