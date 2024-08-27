import { usePage } from "@inertiajs/react";

export const useUserInviteUuid = (): string => {
    return usePage<{ inviteUuid: string }>().props.inviteUuid;
};
