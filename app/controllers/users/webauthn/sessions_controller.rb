# typed: true

# frozen_string_literal: true

module Users
    module Webauthn
        class SessionsController < ApplicationController
            extend T::Sig
            include Authentication

            skip_before_action :authenticate_user!

            before_action :verify_valid_phone, only: %i[create]

            def create
                user = User.find_by(phone:)

                if user&.has_passkey?
                    get_options =
                        relying_party.options_for_authentication(
                            allow_credentials: user.passkeys.map { |p| { id: p.external_id, type: "public-key" } },
                            user_verification: "required",
                        )

                    session[:current_authentication] = { challenge: get_options.challenge, phone: }

                    render json: get_options
                elsif phone.present?
                    if ENV.fetch("SKIP_PHONE_VERIFICATION", nil).present?
                        session[:phone] = phone
                        render json: { success: true }, status: :accepted
                    else
                        render json: { success: send_phone_verification(session, phone) }, status: :accepted
                    end
                else
                    render json: { success: false }, status: :unprocessable_entity
                end
            end

            def callback
                user = User.find_by(phone: session.dig(:current_authentication, "phone"))
                raise "user #{session.dig(:current_authentication, "phone")} never initiated sign up" unless user

                begin
                    verified_webauthn_passkey, stored_passkey =
                        relying_party.verify_authentication(
                            public_key_credential_params,
                            session.dig(:current_authentication, "challenge"),
                            user_verification: true,
                        ) do |webauthn_passkey|
                            user
                                .passkeys
                                .where(external_id: [webauthn_passkey.id, Base64.strict_encode64(webauthn_passkey.raw_id)])
                                .first
                        end

                    stored_passkey.update!(sign_count: verified_webauthn_passkey.sign_count)
                    sign_in(user)

                    session[:verified_phone] = user.phone
                    if user.is_registration_complete
                        route_component(legislators_path)
                    else
                        route_component(sway_registration_index_path)
                    end
                rescue WebAuthn::Error => e
                    render json: { success: false, message: "Verification failed: #{e.message}" }, status: :unprocessable_entity
                ensure
                    session.delete(:current_authentication)
                end
            end

            def destroy
                sign_out
            end

            private

            def session_params
                params.permit(:phone, :publicKeyCredential, :token)
            end

            def public_key_credential_params
                params.require(:publicKeyCredential)
            end

            sig { returns(T.nilable(String)) }
            def phone
                @phone ||= session_params[:phone]&.remove_non_digits
            end

            def verify_valid_phone
                return unless phone.blank? || phone&.size != 10

                redirect_to(root_path, errors: { phone: "Phone must be 10 digits." })
            end
        end
    end
end
