// import SwayFireClient from "@sway/fire";
// import { get } from "lodash";
// import { sway } from "sway";

// export const seedLocales = async (
//     swayFire: SwayFireClient,
//     localeName: string,
// ): Promise<sway.ILocale | undefined> => {
//     console.log("Seeding Locale -", localeName);
//     const [city, region, country] = localeName.split("-");

//     const locale = await swayFire
//         .locales()
//         .create(city, region, country).catch(console.error);
//     if (!locale) {
//         console.error("Could not create locale. Skipping rest of seeds.");
//         return;
//     }

//     return locale;
// };
