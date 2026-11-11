/**
 // @lat: [[bill-creator-test-fixture-overrides#fixtureOverride reads an explicit null correctly]]
 */
const fixtureOverride = <O, K extends keyof O, F>(overrides: O, key: K, fallback: F): Exclude<O[K], undefined> | F =>
    Object.hasOwn(overrides as object, key) ? (overrides[key] as Exclude<O[K], undefined>) : fallback;

export default fixtureOverride;
