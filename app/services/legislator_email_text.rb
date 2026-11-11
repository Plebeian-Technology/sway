# frozen_string_literal: true

require "uri"

# @lat: [[outbound-email#Outbound email#The preview is built from the object the mailer renders]]
class LegislatorEmailText
  def initialize(user_legislator_email)
    @user_legislator_email = user_legislator_email
  end

  def subject
    uv = @user_legislator_email.user_vote

    if uv.present?
      "#{(uv.support == "FOR") ? "Support" : "Oppose"} Bill #{bill.external_id}"
    else
      "Bill #{bill.external_id}"
    end
  end

  def intro
    "Hello #{legislator.active_term&.title} #{legislator.last_name}, my name is #{user_full_name} and #{registered_voter_text} reside #{residence_text}#{address_text}."
  end

  def body
    core_text =
      if @user_legislator_email.user_vote.present?
        "Please #{user_vote_support_text} bill #{bill.external_id} #{bill.title}"
      else
        "I am writing to you today because I would like to know your position on bill #{bill.external_id} #{bill.title}"
      end

    if bill_link.present?
      "#{core_text}, #{bill_link_text}"
    else
      "#{core_text}."
    end
  end

  def conclusion
    "Thank you, #{user_full_name}."
  end

  def bill_link
    link = bill.link
    return nil if link.blank?
    return nil if SummaryCitationValidator.generic_search_url?(link)

    uri = URI.parse(link.to_s.strip)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    return nil if uri.host.blank?

    hostname = uri.host.downcase
    pathname = (uri.path || "").downcase.sub(%r{/+$}, "")

    configured_portal_urls = @user_legislator_email.sway_locale&.generic_portal_urls || []
    matches_generic_portal = configured_portal_urls.any? do |portal_url|
      portal_uri = URI.parse(portal_url.to_s.strip)
      portal_host = portal_uri.host&.downcase
      portal_path = (portal_uri.path || "").downcase.sub(%r{/+$}, "")
      hostname == portal_host && pathname == portal_path
    rescue URI::InvalidURIError, ArgumentError
      false
    end
    return nil if matches_generic_portal

    link
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

  def as_props
    {
      subject: subject,
      intro: intro,
      body: body,
      conclusion: conclusion,
      bill_link: bill_link
    }
  end

  private

  def user_full_name
    user.full_name.presence || "{YOUR NAME}"
  end

  def bill_link_text
    "which can be found here - "
  end

  def user_vote_support_text
    if @user_legislator_email.user_vote.support == "FOR"
      "support"
    else
      "oppose"
    end
  end

  def registered_voter_text
    user.is_registered_to_vote? ? "I am registered to vote and" : "I"
  end

  def residence_text
    if legislator.at_large?
      "in #{@user_legislator_email.sway_locale.city.titleize}"
    else
      "in your district"
    end
  end

  def address_text
    if user.address&.full_address.present?
      " at #{user.address&.full_address}"
    else
      ""
    end
  end

  def legislator
    @legislator ||= @user_legislator_email.legislator
  end

  def user
    @user ||= @user_legislator_email.user
  end

  def bill
    @bill ||= @user_legislator_email.bill
  end
end
