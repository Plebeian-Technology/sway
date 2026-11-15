---
lat:
  mode: explanation
---
# Malformed passkey credentials

A passkey payload the WebAuthn gem cannot decode is refused the same way as one that fails verification. Every enrollment and sign-in callback answers it with its existing invalid-credential response.

## An unreadable credential is an invalid credential

A passkey response that cannot be decoded proves nothing about who sent it, so it is refused exactly like a forged or mismatched one, never with a server error.

[[app/lib/sway_relying_party.rb#SwayRelyingParty]] is the relying party that [[app/controllers/concerns/relying_party.rb]] builds for every callback. Its two verify methods turn a decoding failure into [[app/lib/sway_relying_party.rb#SwayRelyingParty#MalformedCredentialError]], a subclass of the gem's own error. Each callback already rescues that error, so a garbled payload reaches the same branch as a failed signature: the web sign-in callbacks redirect home with a fixed sign-in retry sentence, the web enrollment callback redirects home with a fixed retry sentence that hides the library text, the add-a-passkey callback answers success false with a fixed retry sentence, and the mobile callbacks answer 401 invalid_credentials and clear the one-use challenge.

The translation sits in one place, not in seven rescue clauses, because the seven call sites already agree on what an invalid credential looks like. A new callback gets the same treatment by calling the shared relying party. The original exception survives as the error's cause. The web sign-in and add-a-passkey callbacks show a fixed sentence held in a controller constant and never echo the library's own message; the log keeps that text. Both web sign-in callbacks and the add-a-passkey callback also send Sentry one warning-level message named after the log event, carrying only the exception class as tag, fingerprint and extra; a malformed credential therefore groups under its own class. The operator chose to report these refusals to Sentry while Sway has few users, and the volume may call for dropping the report once it grows.

## Every refusal is logged where it is translated

The relying party logs each decoding failure it translates as a warning, naming the ceremony and the original exception, before raising the malformed-credential error.

The log sits in the relying party rather than in the callbacks because the two mobile callbacks log nothing when they refuse a credential. Before the translation existed, a decoding failure there surfaced as a reported server error. Translating it without a log would have turned a genuine defect, such as a gem or configuration bug that raises one of the listed exception classes, into a silent "invalid credential" on mobile. The web callbacks still write their own warning as well, so a web refusal appears twice in the log: once naming the decoding error, once naming the callback.

## Which decoding failures escape the WebAuthn gem

WebAuthn 3.5.1 wraps very few of its decoding failures in its own error class, so a malformed payload surfaces as an ordinary Ruby exception from whichever library tripped.

Probing the gem with corrupted fake-authenticator payloads showed each of these escaping verify_registration or verify_authentication:

- EOFError and IOError, from truncated CBOR and from authenticator data too short for its binary layout.
- CBOR::MalformedFormatError, a CBOR::UnpackError, from bytes that are not CBOR at all.
- ArgumentError, from a field that is not valid base64url.
- JSON::ParserError, from client data that is not JSON.
- NoMethodError and TypeError, from a missing field or a field of the wrong JSON type. Valid CBOR or JSON holding the wrong inner types reaches them too.
- COSE::MalformedKeyError, a COSE::Error, from a corrupted public key.
- OpenSSL errors, from a signature or attestation certificate that does not parse.
- RuntimeError, which the gem raises bare for a wrong type field or an id that does not match rawId.

Only an empty authenticator data field was already reported as a WebAuthn error. The list is wide because the failures are, but it is a fixed list of classes rather than every StandardError, and it applies only inside the gem's own decoding.

## The stored-passkey lookup keeps its own errors

The sign-in callbacks pass verify_authentication a block that finds the stored passkey. That block is application code, so an exception it raises is not treated as an unreadable credential.

The relying party notes when that lookup is running. An error that escapes while it runs is raised again unchanged, so a defect in the lookup still surfaces instead of hiding behind the generic refusal. This keeps UnknownPasskeyError on its own refusal path, described in [[identity-and-access#Identity and access#The sign-in challenge says which ceremony to run#A missing stored passkey must stop verification before key access]]. A decoding failure after the lookup has returned is still translated. The tests that pin all of this are listed in [[malformed-passkey-credential-tests]].
