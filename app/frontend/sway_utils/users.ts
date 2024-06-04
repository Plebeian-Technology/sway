import { sway } from "sway";

export const getFullUserAddress = (user: sway.IUser) => {
    let address = "";
    if (!user.address) {
        return address;
    }

    if (user.address.street) {
        address += user.address.street + ", ";
        if (user.address.street2) {
            address += user.address.street2 + " ";
        }
    }

    if (user.address.city) {
        address += user.address.city + ", ";
    }

    if (user.address.regionCode) {
        address += user.address.regionCode + " ";
    }

    if (user.address.postalCode) {
        address += user.address.postalCode;
    }

    return address;
};
