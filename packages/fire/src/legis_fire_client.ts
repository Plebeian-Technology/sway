/** @format */

import { sway } from "sway";
import FireBills from "./fire_bills";
import FireBillScores from "./fire_bill_scores";
import FireLegislators from "./fire_legislators";
import FireLegislatorVotes from "./fire_legislator_votes";
import FireUserLegislatorScores from "./fire_user_legislator_scores";
import FireUserLegislatorVotes from "./fire_user_legislator_vote";
import FireUserVotes from "./fire_user_votes";
import FireUsers from "./fire_users";
import FireLegislatorDistrictScores from "./fire_district_legislator_scores";
import FireOrganizations from "./fire_organizations";
import FireUserSettings from "./fire_user_settings";
import FireUserInvites from "./fire_user_invites";
import FireUserBillShares from "./fire_user_bill_shares";

class SwayFireClient {
    firestore: any;
    locale?: sway.ILocale | null;
    firestoreConstructor?: any;

    constructor(
        firestore: any,
        locale: sway.ILocale | null | undefined,
        firestoreConstructor?: any,
    ) {
        this.firestore = firestore;
        this.firestoreConstructor = firestoreConstructor;
        this.locale = locale ? locale : null;
    }

    public name = (): string | undefined => this.locale?.name;

    public bills = () => {
        if (!this.locale) throw new Error("must invoke bills with locale");

        return new FireBills(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
        );
    };

    public billScores = () => {
        if (!this.locale) throw new Error("must invoke billScores with locale");

        return new FireBillScores(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
        );
    };

    public legislators = () => {
        if (!this.locale) throw new Error("must invoke legislators with locale");

        return new FireLegislators(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
        );
    };

    public legislatorVotes = () => {
        if (!this.locale) throw new Error("must invoke legislatorVotes with locale");

        return new FireLegislatorVotes(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
        );
    };

    public userLegislatorScores = () => {
        if (!this.locale) throw new Error("must invoke userLegislatorScores with locale");

        return new FireUserLegislatorScores(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
        );
    };

    public userDistrictScores = () => {
        if (!this.locale) throw new Error("must invoke userDistrictScores with locale");

        return new FireLegislatorDistrictScores(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
        );
    };

    public users = (uid: string) => {
        return new FireUsers(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            uid,
        );
    };

    public userBillShares = (uid: string) => {
        if (!this.locale) throw new Error("must invoke userBillShares with locale");

        return new FireUserBillShares(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            uid,
        );
    }

    public userSettings = (uid: string) => {
        return new FireUserSettings(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            uid,
        );
    };

    public userInvites = (uid: string) => {
        return new FireUserInvites(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            uid,
        );
    };

    public userVotes = (uid: string) => {
        if (!this.locale) throw new Error("must invoke userVotes with locale");

        return new FireUserVotes(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            uid,
        );
    };

    public userLegislatorVotes = (uid: string) => {
        if (!this.locale) throw new Error("must invoke userLegislatorVotes with locale");

        return new FireUserLegislatorVotes(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            uid,
        );
    };

    public organizations = () => {
        if (!this.locale) throw new Error("must invoke organizations with locale");

        return new FireOrganizations(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
        );
    };
}

export default SwayFireClient;
