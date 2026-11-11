---
mode: explanation
summary: "Explains why SkipPhoneVerificationProvisioner is hard-gated to Rails.env.local?, why it never writes admin rights, and the crossed-settings bug it once had."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why SkipPhoneVerificationProvisioner is built the way it is

`SkipPhoneVerificationProvisioner.call` is a second lock on the door.
`PhoneVerificationController#update` calls this without anyone being
logged in, whenever the `SKIP_PHONE_VERIFICATION` environment variable is
set — and `.env.example` ships with it set. It builds a complete,
ready-to-use account for whatever phone number a visitor typed, with no
SMS check at all. So it must never run anywhere but development and
test: one copied env file, or one bad `kamal env push`, would turn
production into a free account factory. `Llm::Client` guards its
environment the same way.

## Why the method never hands out admin rights

Whether someone is an admin comes only from the `ADMIN_PHONES` list —
`User#is_admin?` ignores the database column and asks `is_sway_admin?`
instead. Writing the column did nothing for permissions, so it was
removed from `#call`.

## Why the provisioner leaves `is_registration_complete` false

`SkipPhoneVerificationProvisioner` sets `verified_phone`
and applies its default user/address side effects, but deliberately
leaves `is_registration_complete` false: registration finishes later,
once the address is captured and the passkey is set up, the same as the
real (non-skipped) flow. `User#is_admin` still reads only from the
`ADMIN_PHONES` list, never from a database column, so a spec checking
this path has to stub that list to a phone the user doesn't hold rather
than checking a dropped column.

## The crossed-settings bug this guarded against

Each field of the seeded `Address` reads the setting that matches its
name. They used to be crossed — `postal_code` read
`DEFAULT_REGION_CODE` and `region_code` read `DEFAULT_POSTAL_CODE` — and
the data only came out right because the `.env` files held the two
values swapped as well.

## Why the spec swaps the whole settings group rather than mutating `ENV`

The real class offers `.call(phone:)`, not the `.new(user).run` shape an
earlier draft assumed. The provisioner reads through the memoized
`Sway::Settings.dev_login` reader, so `spec/services/skip_phone_verification_provisioner_spec.rb`
swaps the whole group instance (`with_app_config`) rather than mutating
`ENV` mid-example — the same memoization-staleness lesson 68-01 measured
against `Sway::Settings` upstream.
