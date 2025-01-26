function compareTwoStrings(first_: string, second_: string): number {
    const first = first_.replace(/\s+/g, "");
    const second = second_.replace(/\s+/g, "");

    if (first === second) return 1; // identical or empty
    if (first.length < 2 || second.length < 2) return 0; // if either is a 0-letter or 1-letter string

    const firstBigrams = new Map();
    for (let i = 0; i < first.length - 1; i++) {
        const bigram = first.substring(i, i + 2);
        const count = firstBigrams.has(bigram) ? firstBigrams.get(bigram) + 1 : 1;

        firstBigrams.set(bigram, count);
    }

    let intersectionSize = 0;
    for (let i = 0; i < second.length - 1; i++) {
        const bigram = second.substring(i, i + 2);
        const count = firstBigrams.has(bigram) ? firstBigrams.get(bigram) : 0;

        if (count > 0) {
            firstBigrams.set(bigram, count - 1);
            intersectionSize++;
        }
    }

    return (2.0 * intersectionSize) / (first.length + second.length - 2);
}

function findBestMatch(mainString: string, targetStrings: string) {
    if (!areArgsValid(mainString, targetStrings))
        throw new Error("Bad arguments: First argument should be a string, second should be an array of strings");

    const ratings = [];
    let bestMatchIndex = 0;

    for (let i = 0; i < targetStrings.length; i++) {
        const currentTargetString = targetStrings[i];
        const currentRating = compareTwoStrings(mainString, currentTargetString);
        ratings.push({ target: currentTargetString, rating: currentRating });
        if (currentRating > ratings[bestMatchIndex].rating) {
            bestMatchIndex = i;
        }
    }

    const bestMatch = ratings[bestMatchIndex];

    return {
        ratings: ratings,
        bestMatch: bestMatch,
        bestMatchIndex: bestMatchIndex,
    };
}

function areArgsValid(mainString: string, targetStrings: string) {
    if (typeof mainString !== "string") return false;
    if (!Array.isArray(targetStrings)) return false;
    if (!targetStrings.length) return false;
    if (
        targetStrings.find(function (s) {
            return typeof s !== "string";
        })
    )
        return false;
    return true;
}

export { compareTwoStrings, findBestMatch };
