# frozen_string_literal: true

# @lat: [[fetched-bills-panel#Why it reads the disk rather than the database]]
module BillCreator
  class FetchedBillsPanelSerializer
    PDF_EXTENSION = ".pdf"
    METADATA_FILENAME = "metadata.json"

    # @lat: [[fetched-bills-panel#Why it is scoped to one locale]]
    def self.call(sway_locale)
      return [] if sway_locale.nil?

      sway_locale_segment = ::Legislation::Paths.sway_locale_segment(sway_locale.name)
      return [] if sway_locale_segment.nil?

      root = ::BillCreator::ResourceCachePanelSerializer.bills_raw_root.join(sway_locale_segment)
      return [] unless root.exist?

      external_ids = root.children.select(&:directory?).map { |d| d.basename.to_s }
      return [] if external_ids.empty?

      bill_index = bills_by_external_id(sway_locale, external_ids)

      external_ids.map { |ext| build_row(root.join(ext), ext, bill_index[ext]) }
        .sort_by { |row| -row[:fetched_at].to_f }
    end

    def self.bills_by_external_id(sway_locale, external_ids)
      # @type var index: Hash[String, bill_match]
      index = {}
      ::Bill
        .where(sway_locale_id: sway_locale.id, external_id: external_ids)
        .pluck(:external_id, :id, :title)
        .each { |ext, id, title| index[ext] = {id: id, title: title} }
      index
    end

    # @lat: [[fetched-bills-panel#Why the walk is done with Dir and File rather than Pathname]]
    def self.build_row(dir, external_id, bill_match)
      dir = dir.to_s
      entries = Dir.children(dir)
      direct_files = entries.filter_map { |entry|
        path = File.join(dir, entry)
        path if File.file?(path)
      }

      metadata_present = direct_files.include?(File.join(dir, METADATA_FILENAME))
      pdf_present = direct_files.any? { |path| File.extname(path) == PDF_EXTENSION }

      newest_mtime = direct_files.map { |path| File.mtime(path) }.max || File.mtime(dir)

      {
        external_id: external_id,
        bill_id: bill_match&.dig(:id),
        title: bill_match&.dig(:title),
        fetched_at: Time.zone.at(newest_mtime),
        pdf_present: pdf_present,
        metadata_present: metadata_present,
        bill_row_exists: !bill_match.nil?
      }
    end
  end
end
