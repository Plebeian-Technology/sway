// @lat: [[mobile-bill-surface-components-design#DistrictVotesPanel]]

export interface DistrictRef {
    name?: string | null;
    number?: number | null;
    region_code?: string | null;
}

export interface BillScoreDistrict {
    district?: DistrictRef | null;
    for?: number | string | null;
    against?: number | string | null;
    legislator_names?: string[] | null;
}

export interface DistrictVoteRow {
    key: string;
    label: string;
    name: string | null;
    number: number;
    forCount: number;
    againstCount: number;
    total: number;
    net: number;
    forPct: number;
    legislatorNames: string[];
    isReaderDistrict: boolean;
}

export interface DistrictVotes {
    rows: DistrictVoteRow[];
    readerRows: DistrictVoteRow[];
    maxVotes: number;
    maxAbsNet: number;
    hasVotes: boolean;
}

export type DistrictMajority = "for" | "against" | "tie";

const countFormatter = new Intl.NumberFormat("en-US");

export const formatVoteCount = (count: number): string => countFormatter.format(count);

const toCount = (value: number | string | null | undefined): number => {
    const count = Number(value || 0);
    return Number.isFinite(count) ? count : 0;
};

const toNames = (value: unknown): string[] =>
    Array.isArray(value)
        ? value.flatMap((name) => (typeof name === "string" && name.trim() !== "" ? [name.trim()] : []))
        : [];

const keyOf = (district: DistrictRef): string =>
    `${district.region_code ?? ""}|${district.number ?? ""}|${district.name ?? ""}`;

const sameDistrict = (a: DistrictRef, b: DistrictRef): boolean => {
    if (typeof a.number === "number" && typeof b.number === "number" && a.region_code && b.region_code) {
        return a.number === b.number && a.region_code === b.region_code;
    }
    return !!a.name && a.name === b.name;
};

const toRow = (
    district: DistrictRef,
    forValue: number | string | null | undefined,
    againstValue: number | string | null | undefined,
    legislatorNames?: unknown,
): DistrictVoteRow => {
    const forCount = toCount(forValue);
    const againstCount = toCount(againstValue);
    const total = forCount + againstCount;
    return {
        key: keyOf(district),
        label: `District ${district.number ?? district.name ?? "?"}`,
        name: district.name ?? null,
        number: district.number ?? 0,
        forCount,
        againstCount,
        total,
        net: forCount - againstCount,
        forPct: total > 0 ? Math.round((forCount / total) * 100) : 0,
        legislatorNames: toNames(legislatorNames),
        isReaderDistrict: false,
    };
};

export const representativesText = (row: Pick<DistrictVoteRow, "legislatorNames">): string | null =>
    row.legislatorNames.length === 0
        ? null
        : `${row.legislatorNames.length === 1 ? "Representative" : "Representatives"}: ${row.legislatorNames.join(", ")}`;

export const districtMajority = (row: Pick<DistrictVoteRow, "forCount" | "againstCount">): DistrictMajority | null => {
    if (row.forCount === 0 && row.againstCount === 0) return null;
    if (row.forCount === row.againstCount) return "tie";
    return row.forCount > row.againstCount ? "for" : "against";
};

export const selectDistrictVotes = (
    scoreDistricts: BillScoreDistrict[] | null | undefined,
    readerDistricts: DistrictRef[] | null | undefined,
): DistrictVotes => {
    const readers: DistrictRef[] = [];
    for (const reader of readerDistricts ?? []) {
        if (reader && reader.number !== 0 && !readers.some((seen) => sameDistrict(seen, reader))) {
            readers.push(reader);
        }
    }

    const entries = (Array.isArray(scoreDistricts) ? scoreDistricts : [])
        .filter((entry) => entry?.district?.number !== 0)
        .map((entry) => {
            const district = entry?.district ?? {};
            const row = toRow(district, entry?.for, entry?.against, entry?.legislator_names);
            row.isReaderDistrict = readers.some((reader) => sameDistrict(reader, district));
            return { district, row };
        })
        .sort((a, b) => a.row.number - b.row.number);

    const rows = entries.map((entry) => entry.row);
    const readerRows = readers.map(
        (reader) =>
            entries.find((entry) => sameDistrict(reader, entry.district))?.row ?? {
                ...toRow(reader, 0, 0),
                isReaderDistrict: true,
            },
    );

    const maxVotes = rows.reduce((acc, row) => Math.max(acc, row.forCount, row.againstCount), 0);
    const maxAbsNet = rows.reduce((acc, row) => Math.max(acc, Math.abs(row.net)), 0);

    return { rows, readerRows, maxVotes, maxAbsNet, hasVotes: rows.length > 0 && maxVotes > 0 };
};
