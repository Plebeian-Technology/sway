import { afterEach, describe, expect, it, vi } from "vitest";
import { create, get, isPasskeySupported } from "app/frontend/sway_utils/webauthn";

const bytesToBase64url = (bytes: number[]) =>
    btoa(String.fromCharCode(...bytes))
        .replace(/\+/g, "-")
        .replace(/\//g, "_")
        .replace(/=+$/, "");

const bufferOf = (bytes: number[]) => new Uint8Array(bytes).buffer;
const bytesOf = (buffer: ArrayBuffer) => Array.from(new Uint8Array(buffer));

// Bytes whose base64url form uses "-" and "_" and needs no padding trimmed back.
const CHALLENGE = [251, 255, 190, 1, 2];
const USER_ID = [7, 8, 9];
const CREDENTIAL_ID = [250, 251, 252, 253];

const creationOptions = {
    rp: { name: "Sway" },
    user: { id: bytesToBase64url(USER_ID), name: "u", displayName: "u" },
    challenge: bytesToBase64url(CHALLENGE),
    pubKeyCredParams: [{ type: "public-key" as const, alg: -7 }],
    excludeCredentials: [{ type: "public-key" as const, id: bytesToBase64url(CREDENTIAL_ID) }],
};

const requestOptions = {
    challenge: bytesToBase64url(CHALLENGE),
    allowCredentials: [{ type: "public-key" as const, id: bytesToBase64url(CREDENTIAL_ID) }],
};

const stubBrowser = ({
    publicKeyCredential,
    credentials,
}: {
    publicKeyCredential: unknown;
    credentials: { create?: unknown; get?: unknown };
}) => {
    vi.stubGlobal("PublicKeyCredential", publicKeyCredential);
    vi.stubGlobal("navigator", { credentials });
};

afterEach(() => {
    vi.unstubAllGlobals();
});

describe("create", () => {
    it("decodes the options and builds the credential JSON when the browser has no JSON helpers", async () => {
        const credential = {
            id: "credential-id",
            rawId: bufferOf(CREDENTIAL_ID),
            type: "public-key",
            authenticatorAttachment: "platform",
            getClientExtensionResults: () => ({ credProps: { rk: true } }),
            response: {
                clientDataJSON: bufferOf([1, 2, 3]),
                attestationObject: bufferOf([251, 255, 190]),
                getTransports: () => ["internal", "hybrid"],
            },
        };
        const createCredential = vi.fn<(options: unknown) => Promise<unknown>>().mockResolvedValue(credential);
        stubBrowser({
            publicKeyCredential: function PublicKeyCredential() {},
            credentials: { create: createCredential },
        });

        const result = await create({ publicKey: creationOptions });

        const { publicKey } = createCredential.mock.calls[0][0] as { publicKey: Record<string, any> };
        expect(bytesOf(publicKey.challenge)).toEqual(CHALLENGE);
        expect(bytesOf(publicKey.user.id)).toEqual(USER_ID);
        expect(bytesOf(publicKey.excludeCredentials[0].id)).toEqual(CREDENTIAL_ID);
        expect(publicKey.user.name).toBe("u");
        expect(publicKey.excludeCredentials[0].type).toBe("public-key");
        expect(result).toEqual({
            id: "credential-id",
            rawId: bytesToBase64url(CREDENTIAL_ID),
            type: "public-key",
            authenticatorAttachment: "platform",
            clientExtensionResults: { credProps: { rk: true } },
            response: {
                clientDataJSON: bytesToBase64url([1, 2, 3]),
                attestationObject: bytesToBase64url([251, 255, 190]),
                transports: ["internal", "hybrid"],
            },
        });
    });

    it("leaves out transports when the browser cannot report them", async () => {
        const credential = {
            id: "credential-id",
            rawId: bufferOf(CREDENTIAL_ID),
            type: "public-key",
            getClientExtensionResults: () => ({}),
            response: { clientDataJSON: bufferOf([1]), attestationObject: bufferOf([2]) },
        };
        stubBrowser({
            publicKeyCredential: function PublicKeyCredential() {},
            credentials: { create: vi.fn<() => Promise<unknown>>().mockResolvedValue(credential) },
        });

        const result = await create({ publicKey: creationOptions });

        expect(Object.keys(result.response).sort()).toEqual(["attestationObject", "clientDataJSON"]);
        expect(result).not.toHaveProperty("authenticatorAttachment");
    });

    it("uses the browser helpers and toJSON when they exist", async () => {
        const parsedOptions = { parsed: true };
        const json = { id: "from-toJSON" };
        const parseCreationOptionsFromJSON = vi.fn<(options: unknown) => unknown>().mockReturnValue(parsedOptions);
        const createCredential = vi.fn<(options: unknown) => Promise<unknown>>().mockResolvedValue({
            toJSON: () => json,
        });
        stubBrowser({
            publicKeyCredential: { parseCreationOptionsFromJSON },
            credentials: { create: createCredential },
        });

        const result = await create({ publicKey: creationOptions });

        expect(parseCreationOptionsFromJSON).toHaveBeenCalledWith(creationOptions);
        expect(createCredential).toHaveBeenCalledWith({ publicKey: parsedOptions, signal: undefined });
        expect(result).toBe(json);
    });

    it("throws when the browser has no PublicKeyCredential", async () => {
        stubBrowser({ publicKeyCredential: undefined, credentials: { create: vi.fn<() => Promise<unknown>>() } });

        await expect(create({ publicKey: creationOptions })).rejects.toThrow("does not support passkeys");
    });
});

describe("get", () => {
    it("decodes the options and builds the assertion JSON when the browser has no JSON helpers", async () => {
        const credential = {
            id: "credential-id",
            rawId: bufferOf(CREDENTIAL_ID),
            type: "public-key",
            getClientExtensionResults: () => ({}),
            response: {
                authenticatorData: bufferOf([251, 255]),
                clientDataJSON: bufferOf([1, 2, 3]),
                signature: bufferOf([190, 191]),
                userHandle: bufferOf(USER_ID),
            },
        };
        const getCredential = vi.fn<(options: unknown) => Promise<unknown>>().mockResolvedValue(credential);
        stubBrowser({ publicKeyCredential: function PublicKeyCredential() {}, credentials: { get: getCredential } });

        const result = await get({ publicKey: requestOptions });

        const { publicKey } = getCredential.mock.calls[0][0] as { publicKey: Record<string, any> };
        expect(bytesOf(publicKey.challenge)).toEqual(CHALLENGE);
        expect(bytesOf(publicKey.allowCredentials[0].id)).toEqual(CREDENTIAL_ID);
        expect(result).toEqual({
            id: "credential-id",
            rawId: bytesToBase64url(CREDENTIAL_ID),
            type: "public-key",
            clientExtensionResults: {},
            response: {
                authenticatorData: bytesToBase64url([251, 255]),
                clientDataJSON: bytesToBase64url([1, 2, 3]),
                signature: bytesToBase64url([190, 191]),
                userHandle: bytesToBase64url(USER_ID),
            },
        });
    });

    it("leaves out userHandle when the authenticator returns none", async () => {
        const credential = {
            id: "credential-id",
            rawId: bufferOf(CREDENTIAL_ID),
            type: "public-key",
            getClientExtensionResults: () => ({}),
            response: {
                authenticatorData: bufferOf([1]),
                clientDataJSON: bufferOf([2]),
                signature: bufferOf([3]),
                userHandle: null,
            },
        };
        stubBrowser({
            publicKeyCredential: function PublicKeyCredential() {},
            credentials: { get: vi.fn<() => Promise<unknown>>().mockResolvedValue(credential) },
        });

        const result = await get({ publicKey: requestOptions });

        expect(result.response).not.toHaveProperty("userHandle");
    });

    it("builds the options without allowCredentials for a discoverable sign-in", async () => {
        const getCredential = vi.fn<(options: unknown) => Promise<unknown>>().mockResolvedValue({
            id: "i",
            rawId: bufferOf([1]),
            type: "public-key",
            getClientExtensionResults: () => ({}),
            response: {
                authenticatorData: bufferOf([1]),
                clientDataJSON: bufferOf([2]),
                signature: bufferOf([3]),
                userHandle: null,
            },
        });
        stubBrowser({ publicKeyCredential: function PublicKeyCredential() {}, credentials: { get: getCredential } });

        await get({ publicKey: { challenge: requestOptions.challenge } });

        const { publicKey } = getCredential.mock.calls[0][0] as { publicKey: Record<string, any> };
        expect(publicKey).not.toHaveProperty("allowCredentials");
    });

    it("uses the browser helpers and toJSON when they exist", async () => {
        const parsedOptions = { parsed: true };
        const json = { id: "from-toJSON" };
        const parseRequestOptionsFromJSON = vi.fn<(options: unknown) => unknown>().mockReturnValue(parsedOptions);
        const getCredential = vi.fn<(options: unknown) => Promise<unknown>>().mockResolvedValue({
            toJSON: () => json,
        });
        stubBrowser({
            publicKeyCredential: { parseRequestOptionsFromJSON },
            credentials: { get: getCredential },
        });

        const result = await get({ publicKey: requestOptions });

        expect(parseRequestOptionsFromJSON).toHaveBeenCalledWith(requestOptions);
        expect(getCredential).toHaveBeenCalledWith({ publicKey: parsedOptions, signal: undefined });
        expect(result).toBe(json);
    });

    it("throws when the browser has no PublicKeyCredential", async () => {
        stubBrowser({ publicKeyCredential: undefined, credentials: { get: vi.fn<() => Promise<unknown>>() } });

        await expect(get({ publicKey: requestOptions })).rejects.toThrow("does not support passkeys");
    });
});

describe("isPasskeySupported", () => {
    it("is false when the browser has no PublicKeyCredential", () => {
        stubBrowser({ publicKeyCredential: undefined, credentials: { create: vi.fn<() => void>() } });

        expect(isPasskeySupported()).toBe(false);
    });

    it("is false when navigator.credentials.create is missing", () => {
        stubBrowser({ publicKeyCredential: function PublicKeyCredential() {}, credentials: {} });

        expect(isPasskeySupported()).toBe(false);
    });

    it("is false when the browser has no navigator.credentials", () => {
        vi.stubGlobal("PublicKeyCredential", function PublicKeyCredential() {});
        vi.stubGlobal("navigator", {});

        expect(isPasskeySupported()).toBe(false);
    });

    it("is true without the JSON helpers, because create() converts the options by hand", () => {
        stubBrowser({
            publicKeyCredential: function PublicKeyCredential() {},
            credentials: { create: vi.fn<() => void>() },
        });

        expect(isPasskeySupported()).toBe(true);
    });
});
