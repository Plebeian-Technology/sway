# frozen_string_literal: true

module Legislation
  # @lat: [[legislation-artifact-relocation#Why the report keeps moved and left-behind counts apart]]
  class ArtifactRelocationService
    # @lat: [[legislation-artifact-relocation#Why the report keeps moved and left-behind counts apart]]
    BILL_KEYED_TREES = {
      "bills/raw" => :directory,
      "bills/text" => :file,
      "hearings" => :file,
      "diffs" => :file
    }.freeze

    def initialize(root: Legislation::Paths.root)
      @root = root
      @report = ArtifactRelocationReport.new
    end

    def call
      BILL_KEYED_TREES.each { |relative, kind| relocate_bill_keyed_tree(relative, kind) }
      relocate_attachments
      @report
    end

    private

    # @lat: [[legislation-artifact-relocation#Why the report keeps moved and left-behind counts apart]]
    def locale_segments
      @locale_segments ||= SwayLocale.all
        .filter_map { |locale| Legislation::Paths.sway_locale_segment(locale.name) }
        .to_set
    end

    def relocate_bill_keyed_tree(relative, kind)
      dir = @root.join(relative)
      return unless dir.directory?

      dir.children.each do |entry|
        next unless (kind == :directory) ? entry.directory? : entry.file?
        next if locale_segments.include?(entry.basename.to_s)

        external_id = entry.basename.to_s.sub(/\.[^.]+\z/, "")
        move(entry, relative, locale_for_external_id(external_id))
      end
    end

    # @lat: [[legislation-artifact-relocation#Why the report keeps moved and left-behind counts apart]]
    def relocate_attachments
      dir = @root.join("attachments")
      return unless dir.directory?

      dir.children.each do |entry|
        next unless entry.file?

        attachment_id = entry.basename.to_s[/\Aattachment-(\d+)\./, 1]
        if attachment_id.nil?
          record_left(entry, "attachments", "the file name does not carry an attachment id")
          next
        end

        move(entry, "attachments", locale_for_attachment_id(attachment_id))
      end
    end

    # @lat: [[legislation-artifact-relocation#Archived bills still own their artifacts]]
    def locale_for_external_id(external_id)
      locales = bills_including_archived.where(external_id: external_id).includes(:sway_locale).map(&:sway_locale).compact.uniq
      resolve_single_locale(locales, "no bill is numbered #{external_id}")
    end

    def locale_for_attachment_id(attachment_id)
      # @lat: [[legislation-artifact-relocation#Why the report keeps moved and left-behind counts apart]]
      owners = BillLlmProvisioning.select do |provisioning|
        entries = provisioning.testimony_attachments
        entries.is_a?(Array) && entries.any? { |e| e.is_a?(Hash) && e["attachment_id"].to_s == attachment_id }
      end
      bill_ids = owners.map(&:bill_id).uniq
      locales = bill_ids.empty? ? [] : bills_including_archived.where(id: bill_ids).includes(:sway_locale).filter_map(&:sway_locale).uniq
      resolve_single_locale(locales, "no bill records attachment #{attachment_id}")
    end

    # @lat: [[legislation-artifact-relocation#Archived bills still own their artifacts]]
    def bills_including_archived
      Bill.unscope(where: :archived_at)
    end

    def resolve_single_locale(locales, absent_reason)
      return [nil, absent_reason] if locales.empty?
      if locales.size > 1
        return [nil, "#{locales.size} jurisdictions claim it: #{locales.map(&:name).sort.join(", ")}"]
      end

      segment = Legislation::Paths.sway_locale_segment(locales.first.name)
      return [nil, "jurisdiction #{locales.first.name.inspect} cannot name a folder"] if segment.nil?

      [segment, nil]
    end

    # @lat: [[legislation-artifact-relocation#Why the report keeps moved and left-behind counts apart]]
    def move(entry, relative, placement)
      segment, reason = placement
      if segment.nil?
        record_left(entry, relative, reason || "no jurisdiction could be named")
        return
      end

      destination_dir = @root.join(relative, segment)
      destination = destination_dir.join(entry.basename)
      if destination.exist?
        record_left(entry, relative, "a file is already at #{relative}/#{segment}/#{entry.basename}")
        return
      end

      FileUtils.mkdir_p(destination_dir)
      FileUtils.mv(entry.to_s, destination.to_s)
      @report.record_moved("#{relative}/#{entry.basename}")
    end

    def record_left(entry, relative, reason)
      @report.record_left("#{relative}/#{entry.basename}", reason)
    end
  end
end
