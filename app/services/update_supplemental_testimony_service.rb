# frozen_string_literal: true

# @lat: [[supplemental-testimony-clear-endpoint-rationale#UpdateSupplementalTestimonyService implementation notes]]
class UpdateSupplementalTestimonyService
  def initialize(bill:, supplemental_testimony: nil, clear_supplemental_testimony: false)
    @bill = bill
    @supplemental_testimony = supplemental_testimony.is_a?(::String) ? supplemental_testimony : nil
    @clear_supplemental_testimony = clear_supplemental_testimony
  end

  # @lat: [[supplemental-testimony-clear-endpoint-rationale#UpdateSupplementalTestimonyService implementation notes]]
  def call
    provisioning = @bill.bill_llm_provisioning || @bill.build_bill_llm_provisioning
    return write(provisioning) if provisioning.new_record?

    provisioning.with_lock { write(provisioning) }
  end

  private

  def write(provisioning)
    attrs = SupplementalTestimonyWrite.attrs(
      value: @supplemental_testimony,
      clear: @clear_supplemental_testimony,
      provisioning: provisioning
    )
    return :noop if attrs.empty?

    # @lat: [[supplemental-testimony-clear-endpoint-rationale#UpdateSupplementalTestimonyService implementation notes]]
    return :noop if provisioning.new_record? && attrs[:supplemental_testimony].nil?

    provisioning.update!(attrs)
    :updated
  end
end
