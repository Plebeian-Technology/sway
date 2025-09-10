# typed: true

class UserLegislatorEmailMailer < ApplicationMailer
    extend T::Sig

    default from: "any_from_address@example.com"

    helper_method :intro, :body, :conclusion, :bill_link

    delegate :link, to: :bill, prefix: true

    sig { params(user_legislator_email: UserLegislatorEmail).void }
    def send_email_to_legislator(user_legislator_email)
        @user_legislator_email = user_legislator_email

        mail(from:, to: to, cc: user.email, reply_to:, subject: subject, track_opens: true, track_clicks: true)
    end

    def intro
        "Hello #{legislator.title} #{legislator.last_name}, my name is #{user.full_name} and #{registered_voter_text} reside #{residence_text}#{address_text}."
    end

    def body
        if @user_legislator_email.user_vote.present?
            "Please #{user_vote_support_text} bill #{bill.external_id} #{bill.title}, #{bill_link_text}"
        else
            "I am writing to you today because I would like to know your position on bill #{bill.external_id} #{bill.title}, #{bill_link_text}"
        end
    end

    def conclusion
        "Thank you, #{user.full_name}."
    end

    private

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
        legislator.at_large? ? "in #{@user_legislator_email.sway_locale.city.titleize}" : "in your district"
    end

    def address_text
        user.address&.full_address.present? ? " at #{user.address&.full_address}" : ""
    end

    def from
        "outreach@sway.vote"
    end

    def reply_to
        @user_legislator_email.user.email
    end

    def to
        legislator_email = legislator.email
        return nil if legislator_email.nil?

        legislator_email = "#{legislator_email.split("@").first}@sway.vote" unless Rails.env.production?
        Rails.logger.info("UserLegislatorEmail.to - Legislator Email is: #{legislator_email}")
        legislator_email
    end

    def subject
        uv = @user_legislator_email.user_vote

        if uv.present?
            "#{uv.support == "FOR" ? "Support" : "Oppose"} Bill #{@user_legislator_email.bill.external_id}"
        else
            "Bill #{@user_legislator_email.bill.external_id}"
        end
    end

    sig { returns(Legislator) }
    def legislator
        @legislator ||= @user_legislator_email.legislator
    end

    sig { returns(User) }
    def user
        @user ||= @user_legislator_email.user
    end

    sig { returns(Bill) }
    def bill
        @bill ||= @user_legislator_email.bill
    end
end
