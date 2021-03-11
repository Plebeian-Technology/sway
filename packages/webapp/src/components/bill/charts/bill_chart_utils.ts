import { get, getTextDistrict, isNumber } from "@sway/utils";
import { sway } from "sway";

/**
 * Adds a default score of 1 if a user has voted
 * and a bill score has not updated to reflect that vote
 *
 * @param {sway.IBillScore} score
 * @param {sway.IUserLocale} userLocale
 * @param {sway.IUserVote} userVote
 * @param {("for" | "against")} support
 * @return {*}  {number}
 */
const defaultScore = (
    score: sway.IBillScore,
    userLocale: sway.IUserLocale,
    userVote: sway.IUserVote,
    support: "for" | "against",
): number => {
    const district = userLocale.district;
    if (!district) return 0;

    if (
        isNumber(get(score, `districts.${district}.for`)) ||
        isNumber(get(score, `districts.${district}.against`))
    ) {
        return 0;
    }

    return userVote && userVote.support === support ? 1 : 0;
};

export const setUserLocaleDistrictAsState = (
    userLocale: sway.IUserLocale,
): sway.IUserLocale => {
    return {
        ...userLocale,
        district: getTextDistrict(userLocale.district) as string,
    };
};

export const collectDistrictScoresForState = (
    userLocale: sway.IUserLocale,
    userVote: sway.IUserVote,
    score: sway.IBillScore,
): sway.IBillScore => {
    const district = getTextDistrict(userLocale.district) as string;
    return Object.keys(score.districts)
        .filter((k: string) => k.startsWith(district))
        .reduce(
            (sum: sway.IBillScore, key: string) => {
                sum.districts[district].for =
                    Number(get(sum, `districts.${district}.for`) || 0) +
                    Number(get(score, `districts.${key}.for`) || 0);

                sum.districts[district].against =
                    Number(get(sum, `districts.${district}.against`) || 0) +
                    Number(get(score, `districts.${key}.against`) || 0);

                return sum;
            },
            {
                districts: {
                    [district]: {
                        for: defaultScore(score, userLocale, userVote, "for"),
                        against: defaultScore(
                            score,
                            userLocale,
                            userVote,
                            "against",
                        ),
                    },
                },
            } as sway.IBillScore,
        );
};

/**
 * Add a user's vote to the bill score count IF billScore.district.userVote.support === 0
 * needed for when a user has just voted on a bill and there are NO previous votes
 * NOT called by congress-district (state) score chart
 *
 * @param {sway.IUserLocale} userLocale
 * @param {sway.IUserVote} userVote
 * @param {sway.IBillScore} score
 * @return {*}  {sway.IBillScore}
 */
export const updateBillScoreWithUserVote = (
    userLocale: sway.IUserLocale,
    userVote: sway.IUserVote,
    score: sway.IBillScore,
): sway.IBillScore => {
    if (!score) return score;

    const support = userVote.support as "for" | "against";
    if (!support) return score;

    const district = userLocale.district;
    if (!district) return score;

    const opposite = support === "for" ? "against" : "for";

    if (
        isNumber(get(score, `districts.${district}.${support}`)) ||
        isNumber(get(score, `districts.${district}.${opposite}`))
    ) {
        return score;
    }


    console.log({
        district,
        support: get(score, `districts.${district}.${support}`),
        opposite: get(score, `districts.${district}.${opposite}`),
    });


    const newScore = {
        ...score,
        districts: {
            ...score.districts,
            [district]: {
                [support]: 1,
                [opposite]: 0,
            },
        },
    } as sway.IBillScore;

    console.log({ score, newScore });

    return newScore;
};
