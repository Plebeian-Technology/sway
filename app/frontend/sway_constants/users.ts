import { sway } from "sway";

export const NON_SERIALIZEABLE_FIREBASE_FIELDS = [
    "accessToken",
    "auth",
    "proactiveRefresh",
    "providerData",
    "providerId",
    "reloadListener",
    "reloadUserInfo",
    "stsTokenManager",
    "tenantId",
    "createdAt",
    "updatedAt",
];

export interface IUserState extends sway.IUser {
    inviteUid: string;
    is_email_verifiedRedux: boolean;
}
