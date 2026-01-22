
/* eslint-disable */
// Utilities to replace @github/webauthn-json

export const base64UrlEncode = (buffer: ArrayBuffer): string => {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    for (let i = 0; i < bytes.byteLength; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    return window.btoa(binary)
        .replace(/\+/g, "-")
        .replace(/\//g, "_")
        .replace(/=+$/, "");
};

export const base64UrlDecode = (base64: string): ArrayBuffer => {
    let input = base64.replace(/-/g, "+").replace(/_/g, "/");
    while (input.length % 4) {
        input += "=";
    }
    const binary = window.atob(input);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes.buffer;
};

// Types corresponding to the JSON format used by webauthn-json

export interface PublicKeyCredentialRequestOptionsJSON {
    challenge: string;
    timeout?: number;
    rpId?: string;
    allowCredentials?: {
        type: "public-key";
        id: string;
        transports?: AuthenticatorTransport[];
    }[];
    userVerification?: UserVerificationRequirement;
    extensions?: AuthenticationExtensionsClientInputs;
}

export interface PublicKeyCredentialCreationOptionsJSON {
    rp: PublicKeyCredentialRpEntity;
    user: {
        id: string;
        name: string;
        displayName: string;
    };
    challenge: string;
    pubKeyCredParams: PublicKeyCredentialParameters[];
    timeout?: number;
    excludeCredentials?: {
        type: "public-key";
        id: string;
        transports?: AuthenticatorTransport[];
    }[];
    authenticatorSelection?: AuthenticatorSelectionCriteria;
    attestation?: AttestationConveyancePreference;
    extensions?: AuthenticationExtensionsClientInputs;
}

export interface PublicKeyCredentialWithAssertionJSON {
    id: string;
    rawId: string;
    response: {
        authenticatorData: string;
        clientDataJSON: string;
        signature: string;
        userHandle?: string;
    };
    type: "public-key";
    authenticatorAttachment?: AuthenticatorAttachment;
    clientExtensionResults: AuthenticationExtensionsClientOutputs;
}

export interface PublicKeyCredentialWithAttestationJSON {
    id: string;
    rawId: string;
    response: {
        attestationObject: string;
        clientDataJSON: string;
        transports?: AuthenticatorTransport[];
        getAuthenticatorData?: () => ArrayBuffer;
        getPublicKey?: () => ArrayBuffer | null;
        getPublicKeyAlgorithm?: () => number;
    };
    type: "public-key";
    authenticatorAttachment?: AuthenticatorAttachment;
    clientExtensionResults: AuthenticationExtensionsClientOutputs;
}

// Helper to convert JSON options to native options
const parseCreationOptionsFromJSON = (options: PublicKeyCredentialCreationOptionsJSON): PublicKeyCredentialCreationOptions => {
    return {
        ...options,
        challenge: base64UrlDecode(options.challenge),
        user: {
            ...options.user,
            id: base64UrlDecode(options.user.id),
        },
        excludeCredentials: options.excludeCredentials?.map((cred) => ({
            ...cred,
            id: base64UrlDecode(cred.id),
        })),
    };
};

const parseRequestOptionsFromJSON = (options: PublicKeyCredentialRequestOptionsJSON): PublicKeyCredentialRequestOptions => {
    return {
        ...options,
        challenge: base64UrlDecode(options.challenge),
        allowCredentials: options.allowCredentials?.map((cred) => ({
            ...cred,
            id: base64UrlDecode(cred.id),
        })),
    };
};

// Main functions

export const create = async (
    { publicKey, signal }: { publicKey: PublicKeyCredentialCreationOptionsJSON; signal?: AbortSignal }
): Promise<PublicKeyCredentialWithAttestationJSON> => {
    const options = parseCreationOptionsFromJSON(publicKey);
    const credential = (await navigator.credentials.create({
        publicKey: options,
        signal,
    })) as PublicKeyCredential;

    if (!credential) throw new Error("Credential creation failed");

    const response = credential.response as AuthenticatorAttestationResponse;

    return {
        id: credential.id,
        rawId: base64UrlEncode(credential.rawId),
        response: {
            attestationObject: base64UrlEncode(response.attestationObject),
            clientDataJSON: base64UrlEncode(response.clientDataJSON),
            transports: response.getTransports ? response.getTransports() : undefined,
        },
        type: credential.type as "public-key",
        authenticatorAttachment: credential.authenticatorAttachment,
        clientExtensionResults: credential.getClientExtensionResults(),
    };
};

export const get = async (
    { publicKey, signal }: { publicKey: PublicKeyCredentialRequestOptionsJSON; signal?: AbortSignal }
): Promise<PublicKeyCredentialWithAssertionJSON> => {
    const options = parseRequestOptionsFromJSON(publicKey);
    const credential = (await navigator.credentials.get({
        publicKey: options,
        signal,
    })) as PublicKeyCredential;

    if (!credential) throw new Error("Credential retrieval failed");

    const response = credential.response as AuthenticatorAssertionResponse;

    return {
        id: credential.id,
        rawId: base64UrlEncode(credential.rawId),
        response: {
            authenticatorData: base64UrlEncode(response.authenticatorData),
            clientDataJSON: base64UrlEncode(response.clientDataJSON),
            signature: base64UrlEncode(response.signature),
            userHandle: response.userHandle ? base64UrlEncode(response.userHandle) : undefined,
        },
        type: credential.type as "public-key",
        authenticatorAttachment: credential.authenticatorAttachment,
        clientExtensionResults: credential.getClientExtensionResults(),
    };
};
