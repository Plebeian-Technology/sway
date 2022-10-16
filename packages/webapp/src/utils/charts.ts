import { isEmptyObject } from "@sway/utils";
import { sway } from "sway";

interface IChartOptions {
    max: number;
    title?: string;
}

export const isEmptyScore = (
    score?: sway.IUserLegislatorScoreV2 | sway.IAggregatedBillLocaleScores | sway.IBillScore,
) => {
    if (!score || isEmptyObject(score)) return true;

    if ("districts" in score) {
        return isEmptyObject(score.districts) || (!score.districts.for && !score.against);
    } else if ("billScores" in score) {
        return isEmptyObject(score.billScores) || !score.countAllUsersInDistrict;
    } else {
        return Object.values(score).every((s) => s === 0);
    }
};

export const getBarChartOptions = ({ max, title }: IChartOptions) => {
    const roundTo: number = ((_max: number) => {
        if (_max < 10) return 10;
        if (_max < 100) return 100;
        if (_max < 500) return 500;
        if (_max < 1000) return 1000;
        if (_max < 2000) return 2000;
        if (_max < 5000) return 5000;
        return 10000;
    })(max);

    return {
        responsive: true,
        maintainAspectRatio: true,
        plugins: {
            legend: {
                display: false,
            },
            title: {
                display: !!title,
                text: title || "",
            },
        },
        scales: {
            x: {
                grid: {
                    display: false,
                },
            },
            y: {
                suggestedMin: 0,
                suggestedMax: Math.ceil(max / roundTo) * roundTo,
                grid: {
                    display: false,
                },
            },
        },
    };
};

export const getPieChartOptions = () => {
    return {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
            x: {
                grid: {
                    display: false,
                },
            },
            y: {
                grid: {
                    display: false,
                },
            },
        },
    };
};

export const getBubbleChartOptions = ({ min, max }: { min: number; max: number }) => {
    const rounded = (limit: number): number => {
        if (limit < 10) return 10;
        if (limit < 100) return 100;
        if (limit < 500) return 500;
        if (limit < 1000) return 1000;
        if (limit < 2000) return 2000;
        if (limit < 5000) return 5000;
        return 10000;
    };

    return {
        responsive: true,
        maintainAspectRatio: false,
        layout: {
            justifyContent: "center",
            padding: 10,
        },
        scales: {
            x: {
                grid: {
                    display: false,
                },
            },
            y: {
                suggestedMin: Math.floor(min / rounded(min)) * rounded(min),
                suggestedMax: Math.ceil(max / rounded(max)) * rounded(max),
                grid: {
                    display: false,
                },
            },
        },
    };
};
