// @lat: [[passkey-only-sms-bootstrap#mobile/src/auth/smsAuth.ts: proving you hold a phone number, before your first passkey]]
import { apiClient } from "../api/client";
import { Routes } from "../api/routes";

interface VerifyResponse {
    sms_verified_token: string;
    expires_at: string;
}

export const smsAuth = {
    async requestCode(phone: string): Promise<void> {
        await apiClient.post<void>(Routes.phoneVerification(), { phone });
    },

    async verifyCode(phone: string, code: string): Promise<VerifyResponse> {
        return apiClient.post<VerifyResponse>(Routes.phoneVerificationVerify(), {
            phone,
            code,
        });
    },
};
