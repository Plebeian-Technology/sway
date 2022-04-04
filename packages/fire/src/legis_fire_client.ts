/** @format */

import { sway } from "sway";
import FireBills from "./fire_bills";
import FireBillScores from "./fire_bill_scores";
import FireLegislators from "./fire_legislators";
import FireLegislatorVotes from "./fire_legislator_votes";
import FireLocales from "./fire_locales";
import FireNotifications from "./fire_notifications";
import FireOrganizations from "./fire_organizations";
import FireUsers from "./fire_users";
import FireUserBillShares from "./fire_user_bill_shares";
import FireUserInvites from "./fire_user_invites";
import FireUserSettings from "./fire_user_settings";
import FireUserVotes from "./fire_user_votes";

class SwayFireClient {
    firestore: any;
    locale?: sway.ILocale | null;
    firestoreConstructor?: any;
    logger?: {
        error: (args: any[]) => void;
        warn: (args: any[]) => void;
        info: (args: any[]) => void;
    };

    constructor(
        firestore: any,
        locale: sway.ILocale | null | undefined,
        firestoreConstructor?: any,
        logger?: {
            error: (args: any[]) => void;
            warn: (args: any[]) => void;
            info: (args: any[]) => void;
        },
    ) {
        this.firestore = firestore;
        this.firestoreConstructor = firestoreConstructor;
        this.locale = locale ? locale : null;
        this.logger = logger;
    }

    public name = (): string | undefined => this.locale?.name;

    public bills = () => {
        if (!this.locale) throw new Error("must invoke bills with locale");

        return new FireBills(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            this.logger,
        );
    };

    public billScores = () => {
        if (!this.locale) throw new Error("must invoke billScores with locale");

        return new FireBillScores(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            this.logger,
        );
    };

    public legislators = () => {
        if (!this.locale)
            throw new Error("must invoke legislators with locale");

        return new FireLegislators(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            this.logger,
        );
    };

    public legislatorVotes = () => {
        if (!this.locale)
            throw new Error("must invoke legislatorVotes with locale");

        return new FireLegislatorVotes(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            this.logger,
        );
    };

    public locales = () => {
        if (!this.locale) throw new Error("must invoke locales with locale");

        return new FireLocales(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            this.logger,
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
        if (!this.locale)
            throw new Error("must invoke userBillShares with locale");

        return new FireUserBillShares(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            uid,
        );
    };

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

    public organizations = () => {
        if (!this.locale)
            throw new Error("must invoke organizations with locale");

        return new FireOrganizations(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            this.logger,
        );
    };

    public notifications = () => {
        if (!this.locale)
            throw new Error("must invoke notifications with locale");

        return new FireNotifications(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            this.logger,
        );
    };
}

export default SwayFireClient;
