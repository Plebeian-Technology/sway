import { BALTIMORE_CITY_LOCALE_NAME, LOCALES } from "src/constants";
import SwayFireClient from "src/fire";
import fetch from "node-fetch";
import { db, firestore } from "../firebase";

const testFireFunction = async () => {
    const locale = LOCALES.find((l) => l.name === BALTIMORE_CITY_LOCALE_NAME);
    if (!locale) return;

    const fireClient = new SwayFireClient(db, locale, firestore);
    const legislator = await fireClient
        .legislators()
        .get("zeke-cohen-2020")
        .catch(console.error);
    if (!legislator) return;

    const url = `https://us-central1-sway-dev-3187f.cloudfunctions.net/getLegislatorUserScores`;

    console.log({
        locale,
        legislator,
    });

    const options = {
        method: "POST",
        headers: {
            Accept: "application/json",
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            data: {
                locale,
                legislator,
            },
        }),
    };
    fetch(url, options)
        .then((response) => response.json())
        .then((json) => console.dir(json, { depth: null }))
        .catch(console.error);
};

testFireFunction();

export default testFireFunction;
