---
mode: explanation
summary: "Why Users::PasskeysController#add_callback reads params.require(:publicKeyCredential) instead of the top-level params -- the useAddPasskey hook nests the credential, and a mismatch here 500s invisibly to stubbed request specs."
status: agent-extracted
related: [docs/explanation/discoverable-passkey-design.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `#add_callback` reads the credential from `publicKeyCredential`

`Users::PasskeysController#add_callback` reads
`params.require(:publicKeyCredential)`, not the bare top-level params. The
`useAddPasskey` hook posts the credential NESTED under
`publicKeyCredential` — unlike the first-registration hook, which spreads
it at the top level.

Passing the bare params here (matching the first-registration shape)
previously made the `webauthn` gem read `credential["id"]` as `nil` and
500 on every real add attempt. This was invisible to the request specs,
which stub `verify_registration` and never exercise the actual param
shape the gem reads; only a browser-driven test caught it.
