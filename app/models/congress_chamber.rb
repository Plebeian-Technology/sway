# frozen_string_literal: true

# @lat: [[congress-chamber-design#Why WHITE_HOUSE is its own constant]]
class CongressChamber
  SENATE = "Senate"

  # @lat: [[congress-chamber-design#Why WHITE_HOUSE is its own constant]]
  WHITE_HOUSE = "White House"

  PRESIDENT = "Pres."
  SENATOR = "Sen."
  REPRESENTATIVE = "Rep."

  TERM_YEARS = {
    SENATOR => 6,
    PRESIDENT => 4,
    REPRESENTATIVE => 2
  }.freeze

  class << self
    # @lat: [[congress-chamber-design#Why title_for takes two signals for the President]]
    def title_for(chamber, president: false)
      return PRESIDENT if president || chamber == WHITE_HOUSE

      (chamber == SENATE) ? SENATOR : REPRESENTATIVE
    end

    # @lat: [[congress-chamber-design#Why an unrecognized title defaults to Representative]]
    def term_years_for(title)
      TERM_YEARS.fetch(title, TERM_YEARS.fetch(REPRESENTATIVE))
    end
  end
end
