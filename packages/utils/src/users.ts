import { sway } from "sway";

export const getFullUserAddress = (user: sway.IUser) => {
    let address = "";

    if (user.address1) {
        address += user.address1 + ", ";
        if (user.address2) {
            address += user.address2 + " ";
        }
    }

    if (user.city) {
        address += user.city + ", ";
    }

    if (user.region) {
        address += user.region + " ";
    }

    if (user.postalCode) {
        if (user.postalCodeExtension) {
            address += user.postalCode + "-" + user.postalCodeExtension;
        } else {
            address += user.postalCode;
        }
    }

    return address;
};
