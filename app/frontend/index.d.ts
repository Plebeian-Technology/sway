/** @format */

declare module "sway" {

    interface IIDObject {
        id: number;
    }

    namespace sway {
        export interface IValidationResult {
            success: boolean;
            message: string;
            data?: Record<string, any>;
        }

        namespace awards {
            type TAwardType = "Vote" | "BillShare" | "Invite" | "Sway";
            type TAwardColor = "blue" | "red" | "black" | "silver" | "gold";
    
            type TAwardByType = {
                [type in TAwardType]: {
                    tooltip: (count: number, city: string) => string;
                    nextTooltip: (nextCount: number, city: string) => string;
                    icons: {
                        [path in TAwardColor]: string;
                    };
                };
            };
        }

        type TOption = { label: string; value: string | number };

        type TSwayLevel = "National" | "Regional" | "Local";
        type TAlertLevel = "info" | "success" | "warning" | "error";

        type TNotificationFrequency = 0 | 1 | 2;
        type TNotificationType = 0 | 1 | 2 | 3;

        type TParty = "D" | "R" | "I" | "X";

        export interface ICloudFunctionResponse {
            success: boolean;
            message: string;
            data: Record<string, any>[] | Record<string, any>;
        }

        interface IAddress extends IIDObject {
            street1: string;
            street2?: string;
            street3?: string;
            city: string;
            stateProvinceCode: string;
            country: string;
            postalCode: string;
            latitude: number;
            longitude: number;
        }

        interface IDistrict extends IIDObject {
            name: string;
            swayLocale: ILocale;
        }

        export interface ILocale extends IIDObject {
            name: string; // ex. baltimore-maryland-united_states, <city>-<region>-<country>
            city: string;
            stateProvinceCode: string;
            country: string;
            districts: IDistrict[]; // ex. MD1
            icon: string;
            timezone: string;
            currentSessionStartDate: string;
        }

        export interface IUserLocale extends ILocale {
            district: string; // ex. MD1
        }

        export interface IAdmin {
            isAdmin: true;
        }

        export interface ILocaleUsers extends ILocale {
            userCount: {
                all: firebase.firestore.FieldValue;
                [district: string]: firebase.firestore.FieldValue;
            };
        }

        export interface IUserInvite extends IIDObject {
            user: IUser;
            invitee_email: string;
            invite_accepted_on_utc: Date;
            invite_expires_on_utc: Date;
        }

        export interface IUser extends IIDObject {

            name: string;
            email: string; // from firebase
            phone: string; // from firebase
            isRegistrationComplete: boolean; // completed the post-sign_up registration process
            isRegisteredToVote: boolean; // is registered to vote at IUserLocale, typically this field will have the same value for all IUserLocales for an IUser
            isEmailVerified: boolean;
            isPhoneVerified: boolean;
            isSwayConfirmed: boolean; // confirmed to reside at IUserLocale, typically this field will have the same value for all IUserLocales for an IUser
            address: IAddress;
            locales: IUserLocale[];
        }

        export interface ICongratulationsSettings {
            isCongratulateOnUserVote: boolean;
            isCongratulateOnInviteSent: boolean;
            isCongratulateOnSocialShare: boolean;
        }

        export interface IUserSettings {
            uid: string;
            notificationFrequency: TNotificationFrequency;
            notificationType: TNotificationType;
            hasCheckedSupportFab: boolean;
            messagingRegistrationToken?: string;
            congratulations: ICongratulationsSettings;
        }

        export interface IUserWithSettings {
            user: IUser;
            settings: IUserSettings;
        }

        export interface IUserWithSettingsAdmin {
            user: IUser;
            settings: IUserSettings;
            isAdmin: boolean;
        }

        export interface IUserVote {

            bill: IBill;
            user: IUser;
            support: sway.TUserSupport | null;
        }

        export type TLegislatorSupport = "for" | "against" | "abstain" | null;
        export type TUserSupport = "for" | "against";

        export interface ILegislatorBillSupport {
            [externalLegislatorId: string]: sway.TLegislatorSupport;
        }

        export interface ILegislatorVote {

            legislator: ILegislator;
            bill: IBill;
            support: TLegislatorSupport;
        }

        export interface IVote {
            votedOnUTC: Date;
            bill: IBill;
        }

        export interface ILegislator {
            party: TParty;
            title: string;
            first_name: string;
            last_name: string;
            externalId: string; // ex. bioguide_id from congress.gov
            active: boolean;
            link: string;
            email: string;
            district: IDistrict;
            phone: string;
            fax?: string;
            address?: IAddress;
            photoURL?: string;
        }

        export interface IUserLegislatorScoreV2 {
            countAgreed: number;
            countDisagreed: number;
            countNoLegislatorVote: number;
            countLegislatorAbstained: number;
        }

        export interface IBaseScore {
            for: number;
            against: number;
        }
        export interface IBillScoreDistrct {
            [district: string]: IBaseScore; // ex. MD1
        }

        export interface IBillScore extends IBaseScore {

            districts: IBillScoreDistrct;
        }

        export interface IBillLocaleScore {
            billFirestoreId: string;
            agreedDistrict: number;
            disagreedDistrict: number;
            agreedAll: number;
            disagreedAll: number;
        }

        export interface ITotalBillLocaleScores {
            billFirestoreIds: string[];
            totalAgreedDistrict: number;
            totalDisagreedDistrict: number;
            totalAgreedAll: number;
            totalDisagreedAll: number;
        }

        export interface IBillLocaleUserCount {
            countAllUsersInLocale: number;
            countAllUsersInDistrict: number;
        }

        export interface IAggregatedBillLocaleScores extends ITotalBillLocaleScores {
            countAllUsersInLocale: number;
            countAllUsersInDistrict: number;
            externalLegislatorId: string;
            billScores: IBillLocaleScore[] | undefined;
        }

        export type TBillChamber = "house" | "senate" | "council" | "both";

        export interface ISwayBillSummaries {
            sway: string;
            swayAudioBucketPath?: string;
            swayAudioByline?: string;
            [key: string]: string;
        }

        interface IExternalSummary {
            text: string;
            source: string;
            billFirestoreId: string;
        }

        type TSharePlatform =
            | "facebook"
            | "whatsapp"
            | "twitter"
            | "reddit"
            | "linkedin"
            | "pintrest"
            | "telegram";
        interface ISharedPlatform {
            email?: number;
            facebook?: number;
            telegram?: number;
            twitter?: number;
            whatsapp?: number;
        }

        interface IUserBillShare {
            platforms: ISharedPlatform;
            billFirestoreId: string;
            uids: string[];
        }

        interface INotification {
            date: string;
        }

        interface IUserSway {
            countBillsShared: number; // if a user has shared a bill in any way
            countAllBillShares: number; // total number of ways in which a user has shared a bill
            countInvitesSent: number;
            countInvitesRedeemed: number;
            countBillsVotedOn: number;
            countFacebookShares: number;
            countTwitterShares: number;
            countTelegramShares: number;
            countWhatsappShares: number;
            countEmailShares: number;
            totalSway: number;
            uids: string[]; // can have duplicates
        }

        export type TBillStatus = "passed" | "failed" | "committee" | "vetoed";
        export type TBillCategory =
            | "police"
            | "health"
            | "housing"
            | "infrastructure"
            | "political reform"
            | "civil rights"
            | "education"
            | "economy"
            | "transportation";

        // Used by UI
        export interface IBill {

            swayReleaseDate?: Date;
            active: boolean;
            level: TSwayLevel;
            externalId: string; // ex. congress_bill_id from congress.gov
            externalVersion: string;
            firestoreId: string;
            title: string;
            link: string;
            summaries: ISwayBillSummaries;
            swaySummary?: string;
            score: IBillScore;
            chamber: TBillChamber;
            sponsorExternalId: string;
            status: TBillStatus;
            introducedDate?: string;
            votedate?: string;
            houseVoteDate?: string;
            senateVoteDate?: string;
            relatedBillIds?: any; // ex. opposite chamber bills
            isTweeted: boolean;
            isInitialNotificationsSent: boolean;
            category: TBillCategory;

            supporters?: string[];
            opposers?: string[];
            abstainers?: string[];
        }

        export interface IBillWithOrgs {
            bill: IBill;
            organizations?: IOrganization[];
        }
        export interface IBillOrgsUserVote extends IBillWithOrgs {
            userVote?: IUserVote;
        }

        export interface IBillOrgsUserVoteScore extends IBillOrgsUserVote {
            score?: IBillScore;
        }

        export interface IOrganization {
            name: string;
            iconPath?: string;
            positions: IOrganizationPositions;
        }
        export interface IOrganizationPositions {
            [billFirestoreId: string]: IOrganizationPosition;
        }
        export interface IOrganizationPosition {
            billFirestoreId: string;
            support: boolean;
            summary: string;
        }

        export interface IFormField {
            name: string;
            subLabel?: string;
            type: "text" | "email" | "tel" | "number" | "boolean" | "date";
            component: "text" | "select" | "textarea" | "generatedText" | "checkbox" | "date";
            label: string;
            isRequired: boolean;
            default?: string | null;
            possibleValues?: sway.TOption[];
            disabled?: boolean;
            generateFields?: string[];
            joiner?: string;
            multi?: true;
            createable?: true;
            autoComplete?: string;
            helperText?: string;
            rows?: number;
            disableOn?: (values: any) => boolean;
            colClass?: number;
            containerClassName?: string;
        }

        export interface IAppState {
            user: sway.IUserWithSettingsAdmin & {
                inviteUid: string;
                isEmailVerifiedRedux: boolean;
                userLocales: sway.IUserLocale[];
            };
            locale: sway.ILocale | sway.IUserLocale | undefined;
            // legislators: {
            //     legislators: sway.ILegislator[];
            // };
        }
    }
}
