/** @format */

import { sway } from "sway";
import { Support } from "../sway_constants";

export const SWAY_COLORS = {
    black: "#363636",
    white: "#fff",
    primaryDark: "#1739fc",
    primary: "rgb(60, 110, 247)",
    primaryLight: "rgb(125, 181, 243)",
    primarySubtle: "#9ec5fe",
    secondaryDark: "#cfd8dc",
    secondary: "rgb(241, 241, 241)",
    // "tertiary": "#ad282fc9",
    tertiary: "#ad282fc9",
    tertiaryLight: "rgb(236, 87, 80)",
    tertiaryLighter: "rgb(238, 118, 114)",
    success: "rgb(95, 207, 137)",
    successLight: "rgb(109, 215, 160)",
    warning: "#ffd600",
    danger: "#eb5d68",
    transparent: "rgb(0, 0, 0, 0)",
};

export const swayDarkRed = "#8B0000";
export const swayRed = "rgb(236, 87, 80)";
export const swaySelectedRed = "rgb(238, 118, 114)";
export const notswaySelectedRed = "rgb(253, 244, 244)";
export const swayDarkBlue = "rgb(60, 110, 247)";
export const swayLightBlue = "rgb(125, 181, 243)";
export const swayBlue = "rgb(88, 174, 248)";
export const selectedBlue = "rgb(217, 237, 253)";
export const swayGreen = "rgb(95, 207, 137)";
export const selectedGreen = "rgb(109, 215, 160)";
export const notSelectedGreen = "rgb(239, 250, 245)";
export const swayPurple = "rgb(102, 51, 153)"; // rebeccapurple
export const swayLightPurple = "rgba(102, 51, 153, 0.5)"; // rebeccapurple
export const swayWhite = "rgb(255, 255, 255)";
export const swayYellow = "#DDB345";
export const swayBlack = "#363636";
export const buttonGray = "rgb(241, 241, 241)";
export const swayGray = "#D1D5D8";
export const swayFont = "Gill Sans";
export const swayBoldFont = "Gill Sans";
export const swayWhiteRGBA = (alpha = "1") => `rgba(255, 255, 255, ${alpha})`;
export const swayRedRGBA = (alpha = "1") => `rgba(235, 57, 65, ${alpha})`;
export const swayGreenRGBA = (alpha = "1") => `rgba(34, 139, 34, ${alpha})`;
export const swayBlueRGBA = (alpha = "1") => `rgba(50,175,255, ${alpha})`;
export const swayBlackRGBA = (alpha = "1") => `rgba(0, 0, 0, ${alpha})`;
export const swayGrayRGBA = (alpha = "1") => `rgba(187, 179, 174, ${alpha})`;

export const floralPalette = ["#ffb56f", "#f98166", "#df5f67", "#adbf86", "#889c8a"];
export const bootsPalette = ["#a9cfe5", "#9ea34c", "#ffda3f", "#eaa0cc", "#e55555"];
export const rainbowPalette = ["#0392cf", "#ee4035", "#f37736", "#fdf498", "#7bc043"];

export const dinosPallette = ["#1778f2", "#99ddff", "#2f4b68", "#bf7f7f", "#e29a9a", "#c2fcff", "#ffffff"];

export const REACT_SELECT_STYLES = {
    control: (provided: any) => ({
        ...provided,
        // backgroundColor: SWAY_COLORS.secondaryLighter,
        // borderColor: SWAY_COLORS.secondaryLight,
        cursor: "pointer",
        paddingTop: "5px",
        paddingBottom: "5px",
    }),
    option: (provided: any) => ({
        ...provided,
        cursor: "pointer",
        paddingTop: "20px",
        paddingBottom: "20px",
    }),
    menuPortal: (provided: any) => ({ ...provided, zIndex: 10000 }),
    menu: (provided: any) => ({
        ...provided,
        zIndex: 10000,
    }),
    menuList: (provided: any) => ({
        ...provided,
        zIndex: 10000,
    }),
};

export const selectedHeaderBackground = (userVote: sway.IUserVote) => {
    let support;
    if (userVote) support = userVote.support;

    if (support && support === Support.For) {
        return selectedGreen;
    } else if (support && support === Support.Against) {
        return swaySelectedRed;
    }
    return selectedBlue;
};

export const selectedButtonColor = (userVote: sway.IUserVote) => {
    let support;
    if (userVote) support = userVote.support;

    if (support && support === Support.For) {
        return {
            bg: selectedGreen,
            border: swayWhite,
            text: swayWhite,
        };
    } else if (support && support === Support.Against) {
        return {
            bg: swaySelectedRed,
            border: swayWhite,
            text: swayWhite,
        };
    }
    return {
        bg: swayWhite,
        border: swayBlue,
        text: swayBlue,
    };
};

export const selectedVoteColor = (userVote: sway.IUserVote) => {
    let support;
    if (userVote) support = userVote.support;

    if (support && support === Support.For) {
        return {
            xBackground: notswaySelectedRed,
            xText: selectedGreen,
            checkBackground: selectedGreen,
            checkText: swayWhite,
        };
    } else if (support && support === Support.Against) {
        return {
            xBackground: swaySelectedRed,
            xText: swayWhite,
            checkBackground: notswaySelectedRed,
            checkText: swaySelectedRed,
        };
    }
    return {
        xBackground: notswaySelectedRed,
        xText: swayRed,
        checkBackground: notSelectedGreen,
        checkText: swayGreen,
    };
};

export const voteColor = (userVote: sway.IUserVote) => {
    if (!userVote) {
        return swayBlue;
    } else if (userVote.support === Support.For) {
        return swayGreen;
    } else if (userVote.support === Support.Against) {
        return swayRed;
    } else {
        return swayBlue;
    }
};

export const cardBackgroundColor = (userVote: sway.IUserVote) => {
    if (!userVote) {
        return swayWhite;
    } else if (userVote.support === Support.For) {
        return swayGreen;
    } else if (userVote.support === Support.Against) {
        return swayRed;
    }
    return swayGray;
};

export const cardTitle = (userVote: sway.IUserVote) => {
    if (userVote) {
        return swayWhite;
    }
    return swayBlue;
};

export const cardContainerStyle = (userVote: sway.IUserVote) => {
    return {
        backgroundColor: cardBackgroundColor(userVote),
        width: "90%",
        margin: 10,
        padding: 0,
        borderWidth: 0,
        borderTopRightRadius: 10,
        borderTopLeftRadius: 10,
        borderBottomLeftRadius: 10,
        borderBottomRightRadius: 10,
        shadowColor: undefined,
        shadowOffset: undefined,
        shadowOpacity: undefined,
        shadowRadius: undefined,
    };
};

// reformat a name, if for example it comes in like:
// Lewis, Robbyn
// or
// Lierman, Brook E.
export const formatFullName = (name: string) => {
    let nameSplit;
    let last;
    if (name.includes(",")) {
        nameSplit = name.split(",");
        return `${nameSplit[1]} ${nameSplit[0]}`;
    }
    nameSplit = name.split(" ");
    const first = nameSplit[0];
    const mid = nameSplit.length > 2 ? nameSplit[1] : null;
    last = nameSplit[nameSplit.length - 1];
    // remove suffix from name
    if (last === "I" || last === "II" || last === "III" || last === "IV" || last === "V") {
        last = nameSplit[nameSplit.length - 2];
    }
    // if name is inverted (last, first) mid may become last name
    // mid name may be letter (C) or letter. (C.)
    // reverse last and mid
    if (last.length < 3 && !!mid) {
        last = mid;
    }
    // if no middle name, mid will be == to last 1 == nameSplit.length - 1
    if (!mid || mid === last || mid.length < 3) {
        return first + " " + last;
    } else {
        return first + " " + mid + " " + last;
    }
};
