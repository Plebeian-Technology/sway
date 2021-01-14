/** @format */

// https://gist.github.com/IceCreamYou/6ffa1b18c4c8f6aeaad2

/**
 * Returns the value at a given percentile in a sorted numeric array.
 * "Linear interpolation between closest ranks" method
 *
 * @param  {} arr
 * @param  {} p
 */
export const percentile = (arr: number[], p: number) => {
    if (arr.length === 0) return 0;
    if (p <= 0) return arr[0];
    if (p >= 1) return arr[arr.length - 1];

    const index = (arr.length - 1) * p;
    const lower = Math.floor(index);
    const upper = lower + 1;
    const weight = index % 1;

    if (upper >= arr.length) return arr[lower];
    return arr[lower] * (1 - weight) + arr[upper] * weight;
}

// Returns the percentile of the given value in a sorted numeric array.
export const percentRank = (arr: number[], v: number) => {
    for (var i = 0, l = arr.length; i < l; i++) {
        if (v <= arr[i]) {
            while (i < l && v === arr[i]) i++;
            if (i === 0) return 0;
            if (v !== arr[i - 1]) {
                i += (v - arr[i - 1]) / (arr[i] - arr[i - 1]);
            }
            return i / l;
        }
    }
    return 1;
}
