---
lat:
  mode: reference
---

# Census TIGERweb query response shape

`Census::Congress#request` (`lib/census.rb`) calls the Census Bureau's TIGERweb ArcGIS `MapServer` endpoint (`CENSUS_QUERY_URL`) and parses the body as JSON in `#data`.

- The shape below was recorded next to that call as an untyped-JSON sketch of what the endpoint returns, transcribed here verbatim — including its own inconsistency in how it spells the per-Congress field (`119` as a literal key in one place, `CD117`/`CD116`/`CD#{CURRENT_CONGRESS_NUMBER}` in others). The field name tracks `Census::CURRENT_CONGRESS_NUMBER` (`CD119` today; see the bump note on that constant) and the exact key TIGERweb sends was not independently re-verified when this was extracted — treat the spelling here as a sketch, not a confirmed contract, if you need to rely on it precisely.

```
{
    displayFieldName: string;
    fieldAliases: { STATE: "STATE"; 119: "119" };
    geometryType: "esriGeometryPolygon";
    spatialReference: { wkid: number; latestWkid: number };
    fields: [
        {
            name: "STATE";
            type: "esriFieldTypeString";
            alias: "STATE";
            length: 2;
        },
        {
            name: "119";
            type: "esriFieldTypeString";
            alias: "119";
            length: 2;
        },
    ];
    features: [
        {
            attributes: { STATE: string; 119?: string; CD117?: string; CD116?: string };
            geometry: {
                rings: [number, number][][];
            };
        },
    ];
}
```

- `Census::Congress#congressional_district` reads `data["features"].first["attributes"]["CD#{CURRENT_CONGRESS_NUMBER}"]` — the live code path uses the `CD#{CURRENT_CONGRESS_NUMBER}` spelling, not the bare `119` key shown in `fieldAliases` above.
- `Census::Congress#request` sends `Accept: application/json` as a header and sets open and read timeouts of `Census::REQUEST_TIMEOUT_SECONDS` (5 seconds).
- Answers treated as unavailable (a `Faraday::Error` that `SwayGeocode::Congress#districts` raises as `SwayGeocode::ServiceUnavailableError`): a non-success HTTP status, a timeout or failed connection, a blank body, a body that is not valid JSON, JSON that is not an object, an object with an `error` key, and a `features` value that is not a list of objects whose `attributes` is an object or absent.
- Answers treated as "no district" (an empty array from `SwayGeocode::Congress#districts`): an object with no `features` key, an empty `features` array, and a feature with no `attributes`.
