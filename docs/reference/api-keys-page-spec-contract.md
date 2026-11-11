---
mode: reference
summary: "Exact text and selectors that spec/system/admin_api_keys_spec.rb depends on in app/frontend/pages/ApiKeys.tsx."
status: agent-extracted
related: []
---

# API Keys page spec contract

`app/frontend/pages/ApiKeys.tsx` is the current-UI API Keys page, moved over
from the old V1 code. `spec/system/admin_api_keys_spec.rb` asserts
against the following exact strings and selectors — changing any of them
requires updating that spec in the same change:

| Element | Exact value |
| --- | --- |
| Create button | `click_button "Create API Key"` |
| Dialog title | `"New API Key"` |
| Dialog body | `"Store this new API Key securely"` |
| Dismiss button | `click_button "I saved my API Key"` |
| Name input | `find("table input", match: :first)` — sits inside a `<table>` |
| Update button id | `#update-<id>` |
| Delete button id | `#delete-<id>` |
| Saved name display | `table td` — plain text in a cell |

## Key display flow

The key is shown once and only once, the same way the old V1 code did it:
the controller's `create` action puts it in `flash[:new_api_key_token]`,
Inertia hands that over on `page.props.flash`, the page displays it, and
when the user dismisses the dialog the `api_keys` prop is re-fetched.
