/** @format */

import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { sway } from "sway";
import fetch from "node-fetch";
import { convert } from "xmlbuilder2";
import { response } from "../httpTools";
import { STATE_NAMES_CODES } from "src/constants";
import { IFunctionsConfig } from "../utils";

const { logger } = functions;

/**
 * Validate a user's mailing address
 *
 * USPS API - https://www.usps.com/business/web-tools-apis/address-information-api.htm
 *
 * @param  {Partial<sway.IUser>} async(data)
 * @param  {CallableContext} context
 */
export const validateMailingAddress = functions.https.onCall(
    async (data: sway.IUser, context: CallableContext) => {
        if (!context?.auth?.uid || data.uid !== context?.auth?.uid) {
            logger.error(
                "Unauthed or uid mismatch request to validateMailingAddress",
            );
            return "Invalid Credentials";
        }

        const { address1, address2, region, city, postalCode } = data;

        const config = functions.config() as IFunctionsConfig;
        const uspsid = config.usps.id;
        if (!uspsid) {
            throw new Error("USPS Key was not found in functions config");
        }

        // @ts-ignore
        const statecode = STATE_NAMES_CODES[region];

        const xml = `
<?xml version="1.0"?>
<AddressValidateRequest USERID="${uspsid}">
    <Revision>1</Revision>
    <Address ID="0">
        <Address1>${address2.toUpperCase()}</Address1>
        <Address2>${address1.toUpperCase()}</Address2>
        <City>${city.toUpperCase()}</City>
        <State>${statecode}</State>
        <Zip5>${postalCode}</Zip5>
        <Zip4/>
    </Address>
</AddressValidateRequest>`;
        //         const xml = `
        // <?xml version="1.0"?>
        // <AddressValidateRequest USERID="${uspsid}">
        //     <Revision>1</Revision>
        //     <Address ID="0">
        //         <Address1>${address2.toUpperCase()}</Address1>
        //         <Address2>${address1.toUpperCase()}</Address2>
        //         <City>${city.toUpperCase()}</City>
        //         <State>${statecode}</State>
        //         <Zip5>${postalCode}</Zip5>
        //         <Zip4/>
        //     </Address>
        // </AddressValidateRequest>`;

        const uspsUrl = `http://production.shippingapis.com/ShippingAPI.dll?API=Verify&XML=${xml}`;

        logger.info("sending usps validation request");
        return fetch(uspsUrl)
            .then((response) => {
                logger.info(
                    "received usps validation response with code -",
                    response.status,
                );
                logger.info(
                    "received usps validation response with status -",
                    response.statusText,
                );

                if (response.ok && response.status < 400) {
                    return response.text();
                }
                throw new Error(
                    `usps validation response status code - ${response.status}`,
                );
            })
            .then((data) => {
                if (!data) {
                    logger.error(
                        "empty validation data response from usps",
                        data,
                    );
                    return response(false, "no usps address");
                }
                logger.info("parsed usps validation data");
                const doc = convert(data, { format: "object" });

                // @ts-ignore
                const address = doc?.AddressValidateResponse?.Address;
                if (!address) {
                    logger.error("empty validation address from usps", doc);
                    return response(false, "no usps address");
                }

                return response(true, "validated address", {
                    // NOTE: Address 1/2 are flipped by usps, Address1 is apt
                    address1: address.Address2,
                    address2: address.Address1,
                    region: address.State,
                    city: address.City,
                    postalCode: address.Zip5,
                    postalCodeExtension: address.Zip4,
                });
            })
            .catch((error: Error) => {
                logger.info("error requesting usps address validation");
                logger.error(error.message);
                logger.error(error.stack);
                return response(false, "error sending to usps");
            });
    },
);
