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
    };
    type: "public-key";
    authenticatorAttachment?: AuthenticatorAttachment;
    clientExtensionResults: AuthenticationExtensionsClientOutputs;
}

const base64urlToBuffer = (value: string): ArrayBuffer => {
    const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
    const binary = atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "="));
    return Uint8Array.from(binary, (character) => character.charCodeAt(0)).buffer;
};

const bufferToBase64url = (buffer: ArrayBuffer): string =>
    btoa(String.fromCharCode(...new Uint8Array(buffer)))
        .replace(/\+/g, "-")
        .replace(/\//g, "_")
        .replace(/=+$/, "");

const decodeCredentialDescriptors = (
    descriptors: PublicKeyCredentialCreationOptionsJSON["excludeCredentials"],
): PublicKeyCredentialDescriptor[] =>
    (descriptors ?? []).map((descriptor) => ({ ...descriptor, id: base64urlToBuffer(descriptor.id) }));

const creationOptionsFromJSON = (
    publicKey: PublicKeyCredentialCreationOptionsJSON,
): PublicKeyCredentialCreationOptions => {
    const { excludeCredentials, ...options } = publicKey;
    return {
        ...options,
        challenge: base64urlToBuffer(publicKey.challenge),
        user: { ...publicKey.user, id: base64urlToBuffer(publicKey.user.id) },
        ...(excludeCredentials && { excludeCredentials: decodeCredentialDescriptors(excludeCredentials) }),
    };
};

const requestOptionsFromJSON = (
    publicKey: PublicKeyCredentialRequestOptionsJSON,
): PublicKeyCredentialRequestOptions => {
    const { allowCredentials, ...options } = publicKey;
    return {
        ...options,
        challenge: base64urlToBuffer(publicKey.challenge),
        ...(allowCredentials && { allowCredentials: decodeCredentialDescriptors(allowCredentials) }),
    };
};

const attestationToJSON = (credential: PublicKeyCredential): PublicKeyCredentialWithAttestationJSON => {
    const response = credential.response as AuthenticatorAttestationResponse;
    return {
        id: credential.id,
        rawId: bufferToBase64url(credential.rawId),
        type: credential.type as "public-key",
        ...(credential.authenticatorAttachment && {
            authenticatorAttachment: credential.authenticatorAttachment as AuthenticatorAttachment,
        }),
        clientExtensionResults: credential.getClientExtensionResults(),
        response: {
            attestationObject: bufferToBase64url(response.attestationObject),
            clientDataJSON: bufferToBase64url(response.clientDataJSON),
            ...(typeof response.getTransports === "function" && {
                transports: response.getTransports() as AuthenticatorTransport[],
            }),
        },
    };
};

const assertionToJSON = (credential: PublicKeyCredential): PublicKeyCredentialWithAssertionJSON => {
    const response = credential.response as AuthenticatorAssertionResponse;
    return {
        id: credential.id,
        rawId: bufferToBase64url(credential.rawId),
        type: credential.type as "public-key",
        ...(credential.authenticatorAttachment && {
            authenticatorAttachment: credential.authenticatorAttachment as AuthenticatorAttachment,
        }),
        clientExtensionResults: credential.getClientExtensionResults(),
        response: {
            authenticatorData: bufferToBase64url(response.authenticatorData),
            clientDataJSON: bufferToBase64url(response.clientDataJSON),
            signature: bufferToBase64url(response.signature),
            ...(response.userHandle && { userHandle: bufferToBase64url(response.userHandle) }),
        },
    };
};

export const isPasskeySupported = (): boolean =>
    typeof PublicKeyCredential !== "undefined" && typeof navigator.credentials?.create === "function";

const requirePublicKeyCredential = () => {
    if (typeof PublicKeyCredential === "undefined") {
        throw new Error("Your browser does not support passkeys. Please use a different browser.");
    }
};

export const create = async ({
    publicKey,
    signal,
}: {
    publicKey: PublicKeyCredentialCreationOptionsJSON;
    signal?: AbortSignal;
}): Promise<PublicKeyCredentialWithAttestationJSON> => {
    requirePublicKeyCredential();

    const { parseCreationOptionsFromJSON } = PublicKeyCredential as any;
    const options =
        typeof parseCreationOptionsFromJSON === "function"
            ? parseCreationOptionsFromJSON.call(PublicKeyCredential, publicKey)
            : creationOptionsFromJSON(publicKey);
    const credential = (await navigator.credentials.create({
        publicKey: options,
        signal,
    })) as PublicKeyCredential;

    if (!credential) throw new Error("Credential creation failed");

    if (typeof (credential as any).toJSON === "function") {
        return (credential as any).toJSON() as PublicKeyCredentialWithAttestationJSON;
    }

    return attestationToJSON(credential);
};

export const get = async ({
    publicKey,
    signal,
}: {
    publicKey: PublicKeyCredentialRequestOptionsJSON;
    signal?: AbortSignal;
}): Promise<PublicKeyCredentialWithAssertionJSON> => {
    requirePublicKeyCredential();

    const { parseRequestOptionsFromJSON } = PublicKeyCredential as any;
    const options =
        typeof parseRequestOptionsFromJSON === "function"
            ? parseRequestOptionsFromJSON.call(PublicKeyCredential, publicKey)
            : requestOptionsFromJSON(publicKey);
    const credential = (await navigator.credentials.get({
        publicKey: options,
        signal,
    })) as PublicKeyCredential;

    if (!credential) throw new Error("Credential retrieval failed");

    if (typeof (credential as any).toJSON === "function") {
        return (credential as any).toJSON() as PublicKeyCredentialWithAssertionJSON;
    }

    return assertionToJSON(credential);
};
