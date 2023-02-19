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

export interface IUserState extends sway.IUserWithSettingsAdmin {
    inviteUid: string;
    isEmailVerifiedRedux: boolean;
}
