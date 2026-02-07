
/* eslint-disable */
// Utilities to replace @github/webauthn-json using native browser methods

// Types corresponding to the JSON format used by webauthn-json
// These are kept for compatibility with the rest of the codebase

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
        // Methods below are not part of JSON serialization but kept for type compatibility if needed
        getAuthenticatorData?: () => ArrayBuffer;
        getPublicKey?: () => ArrayBuffer | null;
        getPublicKeyAlgorithm?: () => number;
    };
    type: "public-key";
    authenticatorAttachment?: AuthenticatorAttachment;
    clientExtensionResults: AuthenticationExtensionsClientOutputs;
}

// Main functions using native browser methods

export const create = async (
    { publicKey, signal }: { publicKey: PublicKeyCredentialCreationOptionsJSON; signal?: AbortSignal }
): Promise<PublicKeyCredentialWithAttestationJSON> => {
    // Use native parseCreationOptionsFromJSON if available
    if (typeof (PublicKeyCredential as any).parseCreationOptionsFromJSON !== "function") {
        throw new Error("Your browser does not support WebAuthn JSON methods (PublicKeyCredential.parseCreationOptionsFromJSON). Please update your browser.");
    }

    const options = (PublicKeyCredential as any).parseCreationOptionsFromJSON(publicKey);
    const credential = (await navigator.credentials.create({
        publicKey: options,
        signal,
    })) as PublicKeyCredential;

    if (!credential) throw new Error("Credential creation failed");

    // Use native toJSON if available
    if (typeof (credential as any).toJSON === "function") {
        return (credential as any).toJSON() as PublicKeyCredentialWithAttestationJSON;
    }

    throw new Error("Your browser does not support WebAuthn JSON methods (credential.toJSON). Please update your browser.");
};

export const get = async (
    { publicKey, signal }: { publicKey: PublicKeyCredentialRequestOptionsJSON; signal?: AbortSignal }
): Promise<PublicKeyCredentialWithAssertionJSON> => {
    // Use native parseRequestOptionsFromJSON if available
    if (typeof (PublicKeyCredential as any).parseRequestOptionsFromJSON !== "function") {
         throw new Error("Your browser does not support WebAuthn JSON methods (PublicKeyCredential.parseRequestOptionsFromJSON). Please update your browser.");
    }

    const options = (PublicKeyCredential as any).parseRequestOptionsFromJSON(publicKey);
    const credential = (await navigator.credentials.get({
        publicKey: options,
        signal,
    })) as PublicKeyCredential;

    if (!credential) throw new Error("Credential retrieval failed");

    // Use native toJSON if available
    if (typeof (credential as any).toJSON === "function") {
        return (credential as any).toJSON() as PublicKeyCredentialWithAssertionJSON;
    }

    throw new Error("Your browser does not support WebAuthn JSON methods (credential.toJSON). Please update your browser.");
};
