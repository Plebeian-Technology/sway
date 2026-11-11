# frozen_string_literal: true

# @lat: [[bill-title-display#Which outbound messages carry the shortened title]]
module BillTitle
  # @lat: [[bill-title-display#How a bill's title is shown]]
  LEGAL_CLAUSE = /[[:space:]]+FOR[[:space:]]+the[[:space:]]+purpose[[:space:]]+of[[:space:]]+/i

  DECK_SEPARATOR = /\A(.+?)[[:space:]]+[–—-][[:space:]]+(.+)\z/

  SURROUNDING_SPACE = /\A[[:space:]]+|[[:space:]]+\z/

  module_function

  # @lat: [[bill-title-display#How a bill's title is shown]]
  def headline(title)
    text = trim(title.to_s)
    return "" if text.empty?

    head = trim(text.split(LEGAL_CLAUSE).first.to_s)
    separated = DECK_SEPARATOR.match(head)
    return trim(separated[1].to_s) if separated

    head.empty? ? text : head
  end

  def trim(text)
    text.gsub(SURROUNDING_SPACE, "")
  end
  private_class_method :trim
end
