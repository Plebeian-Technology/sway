/** @format */

import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { sway } from "sway";

// const { logger } = functions;

interface IDataOrganizationPositions {
    [key: string]: {
        support?: boolean;
        oppose?: boolean;
        position: string;
    };
}

interface IDataLegislatorVotes {
    [key: string]: "for" | "against" | "abstain";
}
interface IData extends Partial<sway.IBill> {
    localeName: string;
    positions: IDataOrganizationPositions;
    legislators: IDataLegislatorVotes;
}

// onRequest for external connections like Express (req/res)
export const createBillOfTheWeek = functions.https.onCall(
    (data: IData, context: CallableContext) => {
        throw new Error(
            "NO LONGER ACCEPTING REQUESTS TO CREATE BILL OF THE WEEK FUNCTION. CREATE THROUGH SEEDS.",
        );
    },
);
