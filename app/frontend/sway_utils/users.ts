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

    if (user.address.region_code) {
        address += user.address.region_code + " ";
    }

    if (user.address.postal_code) {
        address += user.address.postal_code;
    }

    return address;
};
