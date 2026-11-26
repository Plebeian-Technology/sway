import * as SecureStore from "expo-secure-store";

import { API_BASE_URL } from "../../src/constants/api";

const mockIconBytes = new TextEncoder().encode("icon-bytes");

jest.mock("expo-file-system", () => ({
    File: jest.fn().mockImplementation((uri: string) => ({
        uri,
        size: 10,
        md5: "4fc1181c062ab30751d78c3e0e969843",
        bytes: async () => mockIconBytes,
    })),
}));

import { directUpload } from "../../src/api/directUpload";

const originalFetch = global.fetch;

const jsonResponse = (body: unknown) =>
    ({ ok: true, status: 200, text: async () => JSON.stringify(body) }) as unknown as Response;

describe("directUpload", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue("T");
        global.fetch = jest.fn() as unknown as typeof fetch;
    });

    afterAll(() => {
        global.fetch = originalFetch;
    });

    it("posts the blob metadata, puts the bytes to the returned URL with the returned headers, and returns the signed id", async () => {
        const uploadHeaders = { "Content-Type": "image/png", "Content-MD5": "T8EYHAYqswdR14w+DpaYQw==" };
        (global.fetch as jest.Mock)
            .mockResolvedValueOnce(
                jsonResponse({
                    signed_id: "signed-blob-id",
                    direct_upload: {
                        url: "https://localhost:3333/rails/active_storage/disk/abc",
                        headers: uploadHeaders,
                    },
                }),
            )
            .mockResolvedValueOnce({ ok: true, status: 204, text: async () => "" } as unknown as Response);

        const signedId = await directUpload({
            uri: "file:///cache/icon.png",
            filename: "icon.png",
            contentType: "image/png",
        });

        expect(signedId).toBe("signed-blob-id");
        expect(global.fetch).toHaveBeenCalledTimes(2);

        const [postUrl, postInit] = (global.fetch as jest.Mock).mock.calls[0];
        expect(postUrl).toBe(`${API_BASE_URL}/rails/active_storage/direct_uploads`);
        expect(postInit.method).toBe("POST");
        expect(postInit.headers.Authorization).toBe("Bearer T");
        expect(JSON.parse(postInit.body)).toEqual({
            blob: {
                filename: "icon.png",
                byte_size: 10,
                checksum: "T8EYHAYqswdR14w+DpaYQw==",
                content_type: "image/png",
            },
        });

        const [putUrl, putInit] = (global.fetch as jest.Mock).mock.calls[1];
        expect(putUrl).toBe("https://localhost:3333/rails/active_storage/disk/abc");
        expect(putInit).toEqual({ method: "PUT", headers: uploadHeaders, body: mockIconBytes });
    });

    it("throws when the storage service refuses the bytes", async () => {
        (global.fetch as jest.Mock)
            .mockResolvedValueOnce(
                jsonResponse({ signed_id: "signed-blob-id", direct_upload: { url: "https://storage/x", headers: {} } }),
            )
            .mockResolvedValueOnce({ ok: false, status: 403, text: async () => "" } as unknown as Response);

        await expect(
            directUpload({ uri: "file:///cache/icon.png", filename: "icon.png", contentType: "image/png" }),
        ).rejects.toThrow();
    });
});
