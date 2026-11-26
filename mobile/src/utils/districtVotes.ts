// @lat: [[mobile-bill-surface-components-design#DistrictVotesPanel]]

export interface DistrictRef {
    name?: string | null;
    number?: number | null;
    region_code?: string | null;
}

export interface BillScoreDistrict {
    district?: DistrictRef | null;
    comparison_suppressed?: boolean | null;
    for_percent?: number | null;
    against_percent?: number | null;
    at_large?: boolean | null;
    legislator_names?: string[] | null;
}

export interface DistrictVoteRow {
    key: string;
    label: string;
    name: string | null;
    number: number;
    forPct: number;
    againstPct: number;
    net: number;
    suppressed: boolean;
    legislatorNames: string[];
    isReaderDistrict: boolean;
}

export interface DistrictVotes {
    rows: DistrictVoteRow[];
    readerRows: DistrictVoteRow[];
}

export type DistrictMajority = "for" | "against" | "tie";

// @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
export const isVoteComparisonSuppressed = (score: object | null | undefined): boolean =>
    (score as { comparison_suppressed?: boolean | null } | null | undefined)?.comparison_suppressed !== false;

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
    forPct: number | null,
    againstPct: number | null,
    legislatorNames?: unknown,
): DistrictVoteRow => ({
    key: keyOf(district),
    label: `District ${district.number ?? district.name ?? "?"}`,
    name: district.name ?? null,
    number: district.number ?? 0,
    forPct: forPct ?? 0,
    againstPct: againstPct ?? 0,
    net: (forPct ?? 0) - (againstPct ?? 0),
    suppressed: forPct === null || againstPct === null,
    legislatorNames: toNames(legislatorNames),
    isReaderDistrict: false,
});

const isDrawn = (entry: BillScoreDistrict | null | undefined): entry is BillScoreDistrict =>
    !!entry &&
    entry.district?.number !== 0 &&
    entry.at_large !== true &&
    !isVoteComparisonSuppressed(entry) &&
    typeof entry.for_percent === "number" &&
    typeof entry.against_percent === "number";

export const representativesText = (row: Pick<DistrictVoteRow, "legislatorNames">): string | null =>
    row.legislatorNames.length === 0
        ? null
        : `${row.legislatorNames.length === 1 ? "Representative" : "Representatives"}: ${row.legislatorNames.join(", ")}`;

export const districtMajority = (
    row: Pick<DistrictVoteRow, "forPct" | "againstPct" | "suppressed">,
): DistrictMajority | null => {
    if (row.suppressed) return null;
    if (row.forPct === row.againstPct) return "tie";
    return row.forPct > row.againstPct ? "for" : "against";
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
        .filter(isDrawn)
        .map((entry) => {
            const district = entry.district ?? {};
            const row = toRow(
                district,
                entry.for_percent ?? null,
                entry.against_percent ?? null,
                entry.legislator_names,
            );
            row.isReaderDistrict = readers.some((reader) => sameDistrict(reader, district));
            return { district, row };
        })
        .sort((a, b) => a.row.number - b.row.number);

    const rows = entries.map((entry) => entry.row);
    const readerRows = readers.map(
        (reader) =>
            entries.find((entry) => sameDistrict(reader, entry.district))?.row ?? {
                ...toRow(reader, null, null),
                isReaderDistrict: true,
            },
    );

    return { rows, readerRows };
};
