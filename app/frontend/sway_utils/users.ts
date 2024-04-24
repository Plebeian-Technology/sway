import { sway } from "sway";

export const getFullUserAddress = (user: sway.IUser) => {
    let address = "";

    if (user.address.street1) {
        address += user.address.street1 + ", ";
        if (user.address.street2) {
            address += user.address.street2 + " ";
        }
    }

    if (user.address.city) {
        address += user.address.city + ", ";
    }

    if (user.address.stateProvinceCode) {
        address += user.address.stateProvinceCode + " ";
    }

    if (user.address.postalCode) {
            address += user.address.postalCode;
    }

    return address;
};
