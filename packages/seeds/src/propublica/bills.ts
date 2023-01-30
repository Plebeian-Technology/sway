import { CONGRESS_LOCALE_NAME } from "@sway/constants";
import { get } from "lodash";
import { sway } from "sway";

export default class PropublicaBills {
    /**
     *
     * Current, no bills are collected from ProPublica
     * For Congress, bills are manually added to the packages/seeds/src/data/united_states/congress/congress/bills/index.ts file
     *
     */
    public getBillsFromFile = async (): Promise<sway.IBill[]> => {
        const [city, region, country] = CONGRESS_LOCALE_NAME.split("-");

        const filepath = `${__dirname}/../data/${country}/${region}/${city}/bills/index.js`;
        const imported = await import(filepath).catch(console.error);

        if (!imported) {
            console.log(
                `PropublicaBills.getBillsFromFile - no bill data from file - ${__dirname}/../data/${country}/${region}/${city}/bills/index.js`,
            );
            return [];
        }

        const data = get(imported, `default.default.${country}.${region}.${city}`) || [];
        return (Array.isArray(data) ? data : data.bills).map(this.addFirestoreIdToBill);
    };

    private addFirestoreIdToBill = (bill: Partial<sway.IBill>): Partial<sway.IBill> => {
        bill.firestoreId = bill.externalVersion
            ? bill.externalId + "v" + bill.externalVersion
            : bill.externalId;
        return bill;
    };
}
