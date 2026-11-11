# frozen_string_literal: true

class RepresentativeReassignmentMailer < ApplicationMailer
  default from: "outreach@sway.vote"

  def reassignment_digest(user, reassignments)
    @user = user
    @reassignments = Array(reassignments)
    return if @user.email.blank? || @reassignments.empty?

    subject = if @reassignments.size == 1
      single_subject(@reassignments.first)
    else
      "Updates to your elected representatives on Sway"
    end

    mail(
      to: @user.email,
      subject: subject
    )
  end

  private

  def single_subject(reassignment)
    case reassignment.reassignment_type
    when "successor_seeded"
      "#{reassignment.legislator&.full_name} is your new representative on Sway"
    when "district_changed"
      "Your voting district has changed on Sway"
    when "vacant_seat"
      "Representation update: Vacant seat in #{reassignment.district&.name || "your district"}"
    when "vacancy_filled"
      "#{reassignment.legislator&.full_name} now represents #{reassignment.district&.name || "your district"}"
    else
      "Updates to your elected representatives on Sway"
    end
  end
end
