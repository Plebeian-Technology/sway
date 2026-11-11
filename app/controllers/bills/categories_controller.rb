# frozen_string_literal: true

# @lat: [[bills-categories-controller-manual-assignment#Why the count-and-insert is inside with_lock]]
module Bills
  class CategoriesController < ApplicationController
    before_action :verify_is_sway_admin

    # @lat: [[bills-categories-controller-manual-assignment#Security notes]]
    def create
      bill = Bill.find(params[:bill_id])
      category = Category.where(active: true).find_by(id: params.require(:category_id))

      if category.nil?
        return redirect_back_with_error(bill, "Category not found or not available.")
      end

      # @lat: [[bills-categories-controller-manual-assignment#Why the count-and-insert is inside with_lock]]
      cap_exceeded = false
      bill.with_lock do
        if BillCategory.exists?(bill_id: bill.id, category_id: category.id)
          # @lat: [[bills-categories-controller-manual-assignment#Why an already-attached category is a no-op success]]
          nil
        elsif bill.categories.where(active: true).count >= Category::MAX_ACTIVE_PER_BILL
          cap_exceeded = true
        else
          BillCategory.find_or_create_by!(bill: bill, category: category)
        end
      end

      if cap_exceeded
        return redirect_back_with_error(
          bill, "Maximum #{Category::MAX_ACTIVE_PER_BILL} categories allowed per bill."
        )
      end

      respond_to do |format|
        format.json { render json: {}, status: :created }
        format.html { redirect_back_or_to(edit_bill_creator_path(bill)) }
      end
    end

    # @lat: [[bills-categories-controller-manual-assignment#Why destroy matches by id only, not active:]]
    def destroy
      bill = Bill.find(params[:bill_id])
      bill_category = BillCategory.find_by(bill_id: bill.id, category_id: params[:id])

      bill_category&.destroy

      respond_to do |format|
        format.json { render json: {}, status: :ok }
        format.html { redirect_back_or_to(edit_bill_creator_path(bill)) }
      end
    end

    private

    def redirect_back_with_error(bill, message)
      respond_to do |format|
        format.json { render_error(code: "validation_failed", message: message, status: :unprocessable_content) }
        format.html do
          redirect_back_or_to(
            edit_bill_creator_path(bill), inertia: {errors: {category: message}}
          )
        end
      end
    end
  end
end
