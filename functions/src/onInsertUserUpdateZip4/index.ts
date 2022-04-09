/** @format */

import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import fetch, { Response } from "node-fetch";
import { convert } from "xmlbuilder2";

const { logger } = functions;

export const onInsertUserUpdateZip4 = functions.firestore
    .document("users/{uid}")
    .onCreate((snap: QueryDocumentSnapshot, _context: EventContext) => {
        const doc: sway.IUser = snap.data() as sway.IUser;
        if (doc.postalCodeExtension) {
            logger.info("user has zip4 already, skipping update");
            return;
        }

        const { address1, address2, region, city, postalCode } = doc;

        const xml = `
<?xml version="1.0"?>
<ZipCodeLookupRequest USERID="${process.env.USPS_ID}">
    <Address ID="0">
        <FirmName/>
        <Address1>${address2?.toUpperCase() || ""}</Address1>
        <Address2>${address1?.toUpperCase() || ""}</Address2>
        <City>${city?.toUpperCase() || ""}</City>
        <State>${region?.toUpperCase() || ""}</State>
        <Zip5>${postalCode}</Zip5>
    </Address>
</ZipCodeLookupRequest>`;
        //         const xml = `
        // <?xml version="1.0"?>
        // <ZipCodeLookupRequest USERID="${process.env.USPS_ID}">
        //     <Address ID="0">
        //         <FirmName/>
        //         <Address1>${address2.toUpperCase()}</Address1>
        //         <Address2>${address1.toUpperCase()}</Address2>
        //         <City>${state.toUpperCase()}</City>
        //         <State>${city.toUpperCase()}</State>
        //         <Zip5>${postalCode}</Zip5>
        //     </Address>
        // </ZipCodeLookupRequest>`;

        const uspsUrl = `http://production.shippingapis.com/ShippingAPI.dll?API=ZipCodeLookup&XML=${xml}`;

        return fetch(uspsUrl)
            .then((response: Response) => {
                if (response.ok && response.status < 300) {
                    return response.text();
                }
                throw new Error(`usps response status code - ${response.status}`);
            })
            .then((data) => {
                if (!data) {
                    logger.error("no data returned from usps -", data);
                    return false;
                }

                const converted = convert(data, { format: "object" });

                // @ts-ignore
                const address = converted?.ZipCodeLookupResponse?.Address;
                if (!address?.Zip4) {
                    logger.error("zip4 from usps was falsey -", address);
                    return false;
                }

                logger.info(`zip4 received from usps ${address.Zip4}`);
                return snap.ref
                    .update({
                        postalCodeExtension: address.Zip4,
                    })
                    .then(() => true);
            })
            .catch(logger.error);
    });
