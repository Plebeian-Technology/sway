# frozen_string_literal: true

# == Schema Information
#
# Table name: categories
# Database name: primary
#
#  id         :integer          not null, primary key
#  active     :boolean          default(TRUE), not null
#  name       :string           not null
#  slug       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_categories_on_active  (active)
#  index_categories_on_name    (name) UNIQUE
#  index_categories_on_slug    (slug) UNIQUE
#

class Category < ApplicationRecord
  # @lat: [[bill-category-assignment-integrity#Why MAX_ACTIVE_PER_BILL is one constant]]
  MAX_ACTIVE_PER_BILL = 3

  # @lat: [[category-name-prompt-injection-surface#Why the length cap is 100 characters]]
  MAX_NAME_CHARS = 100

  # @lat: [[category-name-prompt-injection-surface#Why only control characters are refused, and why all of them]]
  NAME_CONTROL_CHARACTERS = /[[:cntrl:]]/

  has_many :bill_categories, dependent: :destroy
  has_many :bills, through: :bill_categories

  # @lat: [[seed-category-slug-key#Why the slug is read-only on the record]]
  attr_readonly :slug

  validates :name, presence: true, uniqueness: true
  # @lat: [[category-name-prompt-injection-surface#Why the fix lives on the model, not the prompt builders]]
  validates :name, length: {maximum: MAX_NAME_CHARS}
  validate :name_is_free_of_control_characters
  validates :slug, presence: true, uniqueness: true
  # @lat: [[seed-category-slug-key#Why the normalized-slug check only runs on create]]
  validate :slug_is_normalized, on: :create
  # @lat: [[seed-category-slug-key#Why slug collisions are checked against active rows only]]
  validate :slugified_name_is_unique

  # @lat: [[seed-category-slug-key#Why slugify transliterates before downcasing]]
  def self.slugify(name)
    ActiveSupport::Inflector.transliterate(name.to_s).downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
  end

  # @lat: [[seed-category-slug-key#Why slug collisions are checked against active rows only]]
  def self.find_slug_collision(name, except_id: nil)
    key = slugify(name)
    return nil if key.blank?
    scope = except_id ? where.not(id: except_id) : all
    scope.find { |category| slugify(category.name) == key }
  end

  def to_builder
    Jbuilder.new do |category|
      category.id id
      category.name name
      category.slug slug
      category.active active
    end
  end

  private

  # @lat: [[category-name-prompt-injection-surface#Testing a scrubbed copy, not the raw name]]
  def name_is_free_of_control_characters
    return if name.blank?

    safe = Sway::Utf8.scrub(name)
    return if safe == name && !safe.match?(NAME_CONTROL_CHARACTERS)

    errors.add(:name, :invalid)
  end

  def slug_is_normalized
    return if slug.blank?
    errors.add(:slug, :invalid) unless slug == self.class.slugify(slug)
  end

  def slugified_name_is_unique
    return if name.blank?
    # @lat: [[seed-category-slug-key#Why slug collisions are checked against active rows only]]
    return unless active?
    errors.add(:name, :taken) if self.class.find_slug_collision(name, except_id: id)
  end
end
