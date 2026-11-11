/**
 // @lat: [[passkey-only-sms-bootstrap#mobile/src/auth/smsAuth.ts: proving you hold a phone number, before your first passkey]]
 */
import { smsAuth } from "../../src/auth/smsAuth";
import { apiClient } from "../../src/api/client";

jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: jest.fn(),
        post: jest.fn(),
        patch: jest.fn(),
        delete: jest.fn(),
    },
}));

describe("smsAuth", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    test("requestCode POSTs /api/v1/phone_verification with phone", async () => {
        (apiClient.post as jest.Mock).mockResolvedValueOnce(undefined);
        await smsAuth.requestCode("+15551112222");
        expect(apiClient.post).toHaveBeenCalledWith("/api/v1/phone_verification", { phone: "+15551112222" });
    });

    test("verifyCode POSTs /api/v1/phone_verification/verify and returns sms_verified_token", async () => {
        const resp = { sms_verified_token: "smsv_abc", expires_at: "2026-12-31T00:00:00Z" };
        (apiClient.post as jest.Mock).mockResolvedValueOnce(resp);
        const out = await smsAuth.verifyCode("+15551112222", "123456");
        expect(apiClient.post).toHaveBeenCalledWith("/api/v1/phone_verification/verify", {
            phone: "+15551112222",
            code: "123456",
        });
        expect(out).toEqual(resp);
    });
});
