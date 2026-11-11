# Administrator newsroom sources interface

The administrator locales interface presents trusted newsroom sources and path policies as read-only configuration.

## Authoritative repository configuration ownership

Locale newsroom sources originate in declarative repository configuration files (`config/sway_locales/*.yml`) rather than mutable database records.

Allowing in-browser modifications to newsroom sources created a hazardous split-brain state where database overrides bypassed code review and diverged from version-controlled locale definitions. Storing source definitions and path policies in version-controlled configuration ensures that every change follows audited pull request workflows, undergoes automated schema validation, and deploys deterministically across environments.

## Read-only presentation in administrative surfaces

The administrative locales surface provides visibility into configured sources and path policies without permitting ad-hoc mutations.

Operators inspecting jurisdiction settings can review active publisher URLs and distinguish between search hints and restricted paths. Displaying these entries as read-only elements with explicit empty states reinforces that jurisdiction governance remains anchored in tested repository declarations, while preserving adjacent administrative controls such as sample address configuration.
