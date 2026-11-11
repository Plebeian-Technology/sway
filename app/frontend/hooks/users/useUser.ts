import { usePage } from "@inertiajs/react";
import { sway } from "sway";

export const useUser = (): sway.IUser => {
    return usePage<sway.IPageProps>().props.user;
};
