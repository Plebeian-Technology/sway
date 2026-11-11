---
lat:
  mode: reference
---
# Browser assertions

Browser checks distinguish visible output from hidden DOM text, script text, and HTML attributes.

- [[spec/rails_helper.rb]]:298 sets `Capybara.ignore_hidden_elements` to false. In this suite, Chrome's `page.text` and `page.has_text?` include hidden DOM and script text; the Inertia `data-page` attribute value is not text. Scope absence checks when hidden text can match. [[spec/system/bill_categories_spec.rb]]:114 is a passing unscoped `have_no_text` counterexample.
- Table cells may concatenate without spaces; inspect actual row text before adding word-boundary regexes. CSS text-transform changes browser text.
- Combobox options live in the listbox popover, not inside the trigger button. Native implicit roles need semantic selectors, not a literal `[role]` attribute.
- Inertia request specs use the maintained matchers. `have_props` nested matchers read raw string-keyed JSON; deep-symbolized accessor output is a different shape. Check the installed matcher before choosing nested keys.
- Check both numeric JSON values and string form values at Ruby boundaries; `Integer(value, 10)` rejects a value already represented as a number.
- For console-capture coverage, DEBUG/INFO distinguishes an ALL logging configuration; WARNING/ERROR can arrive under default settings.
- For narrow layouts, assert `window.innerWidth` after emulation. Ordinary window resizing may enforce a wider minimum. Text-node overflow needs Range measurements as well as element rectangles.
- Current helpers are in `spec/support/`; use their implementation rather than ad hoc setup commands.
