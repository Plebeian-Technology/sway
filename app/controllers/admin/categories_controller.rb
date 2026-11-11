# frozen_string_literal: true

# @lat: [[admin-categories-controller-design#Categories.tsx, the frontend page]]
# @lat: [[admin-categories-controller-design#Why it inherits ApplicationController directly, and the mass-assignment guard]]
module Admin
  class CategoriesController < ApplicationController
    before_action :verify_is_sway_admin

    DEACTIVATED_COLLISION_COPY = "A category with that name is deactivated. Reactivate it instead."

    def index
      render_inertia_or_json(page: Pages::ADMIN_CATEGORIES, props: index_props)
    end

    # @lat: [[admin-categories-controller-design#create: why the empty-name and punctuation-only checks come first]]
    def create
      attrs = params.require(:category).permit(:name)
      name = attrs[:name].to_s.strip

      return respond_with_name_error("Category name is required.") if name.blank?

      if Category.slugify(name).blank?
        return respond_with_name_error("Category name must contain at least one letter or number.")
      end

      # @lat: [[admin-categories-controller-design#create: why the collision check runs in two directions]]
      new_slug = Category.slugify(name)
      name_collision = Category.find_slug_collision(name)
      if name_collision
        copy = name_collision.active? ? "Category name is already taken." : DEACTIVATED_COLLISION_COPY
        return respond_with_name_error(copy)
      end
      if Category.find_by(slug: new_slug)
        return respond_with_name_error("Category name is already taken.")
      end

      category = Category.create!(name: name, slug: new_slug)
      rearm_unmatched_categorization!
      respond_to do |format|
        format.json { render json: category.to_builder.attributes!, status: :created }
        format.html { redirect_to admin_categories_path, notice: "Category added." }
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_with_name_error(name_error_copy(e.record))
    rescue ActiveRecord::RecordNotUnique
      # @lat: [[admin-categories-controller-design#create: why RecordNotUnique gets its own rescue]]
      respond_with_name_error("Category name is already taken.")
    end

    # @lat: [[seed-category-slug-key#Why the slug is read-only on the record]]
    def update
      category = Category.find(params[:id])
      attrs = params.require(:category).permit(:name, :active)

      # @lat: [[admin-categories-controller-design#update: why the rename collision check also covers current names]]
      if attrs[:name].present?
        new_name = attrs[:name].to_s.strip
        new_slugified = Category.slugify(new_name)
        return respond_with_name_error("Category name must contain at least one letter or number.") if new_slugified.blank?

        if Category.find_slug_collision(new_name, except_id: category.id)
          return respond_with_name_error("Category name is already taken.")
        end

        attrs[:name] = new_name
      end

      # @lat: [[admin-categories-controller-design#update: why reactivation is blocked against the per-bill cap]]
      if reactivating?(category, attrs) && reactivation_would_exceed_cap?(category)
        return respond_with_name_error(
          "Reactivating would exceed the 3-category limit on one or more bills. Remove a category from those bills first."
        )
      end

      category.update!(attrs)
      rearm_unmatched_categorization!
      notice = notice_for(category)
      respond_to do |format|
        format.json { render json: category.to_builder.attributes! }
        format.html { redirect_to admin_categories_path, notice: notice }
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_with_name_error(name_error_copy(e.record))
    end

    # @lat: [[admin-categories-controller-design#destroy: two-step delete and why it skips the re-arm]]
    def destroy
      category = Category.find(params[:id])
      if category.active?
        return respond_with_name_error("Deactivate the category before deleting it.")
      end

      # @lat: [[admin-categories-controller-design#destroy: two-step delete and why it skips the re-arm]]
      category.destroy!
      respond_to do |format|
        format.json { head :no_content }
        format.html { redirect_to admin_categories_path, notice: "Category deleted." }
      end
    end

    private

    # @lat: [[admin-categories-controller-design#Why the re-arm is global rather than diffed against what changed]]
    # @lat: [[backfill-bill-categories-scope#Why the unmatched-stamp log is at warn, not silent]]
    def rearm_unmatched_categorization!
      BillLlmProvisioning
        .where.not(categories_unmatched_at: nil)
        .update_all(categories_unmatched_at: nil)
    end

    # @lat: [[admin-categories-controller-design#update: why reactivation is blocked against the per-bill cap]]
    def reactivating?(category, attrs)
      return false unless ActiveModel::Type::Boolean.new.cast(attrs[:active])
      !category.active?
    end

    # @lat: [[admin-categories-controller-design#update: why reactivation is blocked against the per-bill cap]]
    def reactivation_would_exceed_cap?(category)
      BillCategory.where(category_id: category.id, bill_id: bills_at_active_cap).exists?
    end

    # @lat: [[admin-categories-controller-design#update: why reactivation is blocked against the per-bill cap]]
    def bills_at_active_cap
      BillCategory
        .joins(:category)
        .where(categories: {active: true})
        .group(:bill_id)
        .having(Arel.sql("COUNT(*) >= #{Category::MAX_ACTIVE_PER_BILL}"))
        .select(:bill_id)
    end

    # @lat: [[admin-categories-controller-design#Categories.tsx, the frontend page]]
    def index_props
      cats = Category.order(:name)
      counts = BillCategory.group(:category_id).count
      {
        categories: cats.map { |c|
          c.to_builder.attributes!.merge("bill_count" => counts[c.id] || 0)
        }
      }
    end

    # @lat: [[admin-categories-controller-design#Why it inherits ApplicationController directly, and the mass-assignment guard]]
    def notice_for(category)
      if category.saved_change_to_name?
        "Category renamed."
      elsif category.saved_change_to_active?
        category.active? ? "Category activated." : "Category deactivated. Existing bill assignments are preserved."
      else
        "Category updated."
      end
    end

    # @lat: [[admin-categories-controller-design#Minor extractions]]
    def name_error_copy(category)
      name_details = category.errors.details[:name]
      slug_details = category.errors.details[:slug]
      if name_details.any? { |d| d[:error] == :blank }
        "Category name is required."
      elsif name_details.any? { |d| d[:error] == :taken } ||
          slug_details.any? { |d| d[:error] == :taken }
        # @lat: [[admin-categories-controller-design#create: why the empty-name and punctuation-only checks come first]]
        "Category name is already taken."
      else
        category.errors.full_messages_for(:name).first || "Category name is invalid."
      end
    end

    # @lat: [[admin-categories-controller-design#Why both create and update answer in two formats]]
    def respond_with_name_error(copy)
      respond_to do |format|
        format.json do
          render_error(
            code: "validation_failed",
            message: copy,
            status: :unprocessable_content,
            details: {category: {name: copy}}
          )
        end
        format.html do
          redirect_to admin_categories_path,
            inertia: {errors: {category: {name: copy}}}
        end
      end
    end
  end
end
