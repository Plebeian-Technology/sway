import * as fs from "fs";
import { isNumber } from "lodash";

import * as data from "./congress/legislators.json";

interface IJsonData {
    street: string | null;
    city: string;
    region: string;
    regionCode: string;
    zip: string;
    first_name: string;
    last_name: string;
    externalId: string;
    bioguideId: string;
    district: string;
    phone: string | null;
    title: string;
    active: boolean;
    twitter: string | null;
    party: string;
    photoURL: string;
    link: string;
    email: string | null;
    level: string;
}

const headers = [
    "Title*",
    "First Name*",
    "Last Name*",
    "External ID (If not assigned by jurisdiction | firstname-lastname-electoralYear)*",
    "In Office (0 = No | 1 = Yes)*",
    "Party (D | R | I | G | L or blank)",
    "District (0 if At-Large)*",
    "Phone",
    "Email",
    "Twitter (@...)",
    "Photo URL (https://...)",
    "Link (https://...)",
    "Street*",
    "Street 2",
    "City*",
    "Region*",
    "Region Code*",
    "Zip Code*",
];

const writeField = (field: string | number | boolean | null) => {
    if (typeof field === "string") return field;
    if (typeof field === "boolean") {
        if (field) return "1";
        return "0";
    }
    if (isNumber(field)) {
        return String(field);
    }
    return "";
};

const congressJsonToCsv = () => {
    const output = `${__dirname}/../../src/congress/legislators.csv`;

    fs.writeFileSync(output, headers.join(",") + "\n", "utf-8");

    data.forEach((item: IJsonData | null) => {
        if (!item) return;

        const _twitter = writeField(item.twitter);
        const twitter = _twitter ? (_twitter.startsWith("@") ? _twitter : `@${_twitter}`) : "";

        fs.appendFile(
            output,
            [
                writeField(item.title),
                writeField(item.first_name),
                writeField(item.last_name),
                writeField(item.externalId),
                writeField(item.active),
                writeField(item.party),
                writeField(item.district),
                writeField(item.phone),
                writeField(item.email),
                twitter,
                writeField(item.photoURL),
                writeField(item.link),
                writeField(item.street),
                writeField(""),
                writeField(item.city),
                writeField(item.region),
                writeField(item.regionCode),
                writeField(item.zip),
            ].join(",") + "\n",
            console.error,
        );
    });
};

// congressJsonToCsv();

export default congressJsonToCsv;
