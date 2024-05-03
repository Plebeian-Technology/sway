/** @format */

declare module "sway" {
    interface IIDObject {
        id: number;
    }

    interface ISelectOption {
        label: string;
        value: string | number;
    }

    namespace sway {

        interface IValidationResult {
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

        interface ICloudFunctionResponse {
            success: boolean;
            message: string;
            data: Record<string, any>[] | Record<string, any>;
        }

        interface IAddress extends IIDObject {
            street: string;
            street2?: string;
            street3?: string;
            city: string;
            regionCode: string;
            country: string;
            postalCode: string;
            latitude: number;
            longitude: number;
        }

        interface IDistrict extends IIDObject {
            name: string;
            number: number;
            regionCode: string;
            // swayLocale: ISwayLocale;
        }

        interface ISwayLocale extends IIDObject {
            name: string; // ex. baltimore-maryland-united_states, <city>-<region>-<country>
            city: string;
            regionCode: string;
            country: string;
            // districts: IDistrict[];
            // icon: string;
            // timezone: string;
            // currentSessionStartDate: string;
        }

        interface IAdmin {
            isAdmin: true;
        }

        interface ISwayLocaleUsers extends ISwayLocale {
            userCount: {
                all: number;
                [district: string]: number;
            };
        }

        interface IUserInvite extends IIDObject {
            user: IUser;
            invitee_email: string;
            invite_accepted_on_utc: Date;
            invite_expires_on_utc: Date;
        }

        interface IUser extends IIDObject {
            id: number;
            // name: string;
            email: string | null;
            phone: string;
            isRegistrationComplete: boolean; // completed the post-sign_up registration process
            isRegisteredToVote: boolean; // is registered to vote at ISwayLocale, typically this field will have the same value for all ISwayLocales for an IUser
            isEmailVerified: boolean;
            isPhoneVerified: boolean;
            isSwayConfirmed: boolean; // confirmed to reside at ISwayLocale, typically this field will have the same value for all ISwayLocales for an IUser
            address: IAddress;
            locales: ISwayLocale[];
        }

        interface ICongratulationsSettings {
            isCongratulateOnUserVote: boolean;
            isCongratulateOnInviteSent: boolean;
            isCongratulateOnSocialShare: boolean;
        }

        interface IUserSettings {
            uid: string;
            notificationFrequency: TNotificationFrequency;
            notificationType: TNotificationType;
            hasCheckedSupportFab: boolean;
            messagingRegistrationToken?: string;
            congratulations: ICongratulationsSettings;
        }


        interface IUserVote {
            bill: IBill;
            user: IUser;
            support: sway.TUserSupport | null;
        }

        type TLegislatorSupport = "for" | "against" | "abstain" | null;
        type TUserSupport = "for" | "against";

        interface ILegislatorBillSupport {
            [externalLegislatorId: string]: sway.TLegislatorSupport;
        }

        interface ILegislatorVote {
            legislator: ILegislator;
            bill: IBill;
            support: TLegislatorSupport;
        }

        interface IVote {
            votedOnUTC: Date;
            bill: IBill;
        }

        interface ILegislator extends IIDObject {
            swayLocaleId: number;
            party: TParty;
            title: string;
            firstName: string;
            lastName: string;
            fullName: string;
            externalId: string; // ex. bioguide_id from congress.gov
            active: boolean;
            link: string;
            email: string;
            district: IDistrict
            phone: string;
            fax?: string;
            address?: IAddress;
            photoUrl?: string;
        }

        interface IUserLegislatorScore {
            userLegislatorId: number;
            legislatorId: number;
            swayLocaleId: number;
            countAgreed: number;
            countDisagreed: number;
            countNoLegislatorVote: number;
            countLegislatorAbstained: number;
        }

        interface IBaseScore {
            for: number;
            against: number;
        }
        interface IBillScoreDistrct extends IBaseScore {
            district: IDistrict;
        }

        interface IBillScore extends IBaseScore {
            bill_id: number;
            districts: IBillScoreDistrct;
        }

        interface IBillLocaleScore {
            billFirestoreId: string;
            agreedDistrict: number;
            disagreedDistrict: number;
            agreedAll: number;
            disagreedAll: number;
        }

        interface ITotalBillLocaleScores {
            billFirestoreIds: string[];
            totalAgreedDistrict: number;
            totalDisagreedDistrict: number;
            totalAgreedAll: number;
            totalDisagreedAll: number;
        }

        interface IBillLocaleUserCount {
            countAllUsersInLocale: number;
            countAllUsersInDistrict: number;
        }

        interface IAggregatedBillLocaleScores extends ITotalBillLocaleScores {
            countAllUsersInLocale: number;
            countAllUsersInDistrict: number;
            externalLegislatorId: string;
            billScores: IBillLocaleScore[] | undefined;
        }

        type TBillChamber = "house" | "senate" | "council" | "both";

        interface ISwayBillSummaries {
            sway: string;
            swayAudioBucketPath?: string;
            swayAudioByline?: string;

            // [key: string]: string;
        }

        interface IExternalSummary {
            text: string;
            source: string;
            billFirestoreId: string;
        }

        type TSharePlatform = "facebook" | "whatsapp" | "twitter" | "reddit" | "linkedin" | "pintrest" | "telegram";
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

        type TBillStatus = "passed" | "failed" | "committee" | "vetoed";
        type TBillCategory =
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
        interface IBill {
            swayReleaseDate?: Date;
            active: boolean;
            level: TSwayLevel;
            externalId: string; // ex. congress_bill_id from congress.gov
            externalVersion: string;
            externalId: string;
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
            createdAt: Date
        }

        interface IBillWithOrgs {
            bill: IBill;
            organizations?: IOrganization[];
        }
        interface IBillOrgsUserVote extends IBillWithOrgs {
            userVote?: IUserVote;
        }

        interface IBillOrgsUserVoteScore extends IBillOrgsUserVote {
            score?: IBillScore;
        }

        interface IOrganization {
            name: string;
            iconPath?: string;
            positions: IOrganizationPositions;
        }
        interface IOrganizationPositions {
            [billFirestoreId: string]: IOrganizationPosition;
        }
        interface IOrganizationPosition {
            billFirestoreId: string;
            support: boolean;
            summary: string;
        }

        interface IFormField {
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

        interface IAppState {
            user: sway.IUser & {
                inviteUid: string;
                isEmailVerifiedRedux: boolean;
                userLocales: sway.ISwayLocale[];
            };
            locales: {
                locales: sway.ISwayLocale[]
                locale: sway.ISwayLocale | undefined;
            }
            // legislators: {
            //     legislators: sway.ILegislator[];
            // };
        }
    }
}
