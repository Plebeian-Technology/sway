import { get, getTextDistrict } from "@sway/utils";
import { sway } from "sway";

const defaultScore = (userVote: sway.IUserVote, support: "for" | "against") => {
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
                        for: defaultScore(userVote, "for"),
                        against: defaultScore(userVote, "against"),
                    },
                },
            } as sway.IBillScore,
        );
};

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

    if (get(score, `districts.[${district}].${support}`)) {
        return score;
    }
    return {
        ...score,
        // eslint-disable-next-line
        // @ts-ignore
        districts: {
            ...score.districts,
            [district]: {
                [support]: 1,
            },
        },
    };
};
