---
lat:
  mode: explanation
---

# Why the CSP reports endpoint handles two body shapes

Firefox and other modern browsers send the newer `reports+json` format: an Array of reports whose body fields are camelCase.

The controller used to call `report["csp-report"]` on that Array, which raised `TypeError: no implicit conversion of String into Integer` and returned a 500 in production on every violation — the older single-object `{"csp-report": {...}}` shape some browsers still send never triggered this, so the bug only showed up against Firefox traffic. The controller now handles both shapes.
