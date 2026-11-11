# frozen_string_literal: true

# @lat: [[legislation-pipeline#The legislation pipeline#Law sections stay within their jurisdiction]]
class MoveArtifactsUnderJurisdictionFolders < ActiveRecord::Migration[8.1]
  def up
    report = Legislation::ArtifactRelocationService.new.call

    say "moved #{report.moved_count} artifact file(s) under their jurisdiction folder"
    return if report.left_count.zero?

    say "left #{report.left_count} alone, each named below with the reason"
    report.left_lines.each { |line| say line, true }
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Moving these files back would put two jurisdictions' bills on one set of names again."
  end
end
