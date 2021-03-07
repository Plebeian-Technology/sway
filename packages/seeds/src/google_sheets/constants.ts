// If modifying these scopes, delete token.json.
export const SCOPES = ["https://www.googleapis.com/auth/spreadsheets.readonly"];
// The file token.json stores the user's access and refresh tokens, and is
// created automatically when the authorization flow completes for the first
// time.
export const TOKEN_PATH = "sheets_token.json";

export const SPREADSHEET_IDS = {
    Example: "1gTg19Lev54xqH744oPCMXrM3vFnLywNxwiTD_ZHAyHE",
};

export const SHEET_HEADERS = {
    Locale: [
        "City*",
        "Region (State)*",
        "Region Code*",
        "Country*",
        "Districts*",
        "Icon*",
    ],
    Legislators: [
        "Title*",
        "First Name*",
        "Last Name*",
        "External ID (If not assigned by jurisdiction, firstname-lastname-electoralYear)*",
        "In Office (0 = No, 1 = Yes)*",
        "Party (D, R, I, G, L or blank)",
        "District (0 if At-Large)*",
        "Phone",
        "Email",
        "Twitter (@...)",
        "Photo URL (if not available, an image that can be uploaded)",
        "Link",
        "Street*",
        "Street 2",
        "Zip Code*"
    ],
    LegislatorVotes: [
        "External Bill ID*",
        "External Bill Version",
        "External Legislator ID*",
        "Legislator Support (For, Against, Abstain)*",
    ],
    Bills: [
        "Title*",
        "External ID*",
        "External Version",
        "Chamber (council, house, senate)*",
        "Status (passed, failed, committee, vetoed)*",
        "Sponsor External ID*",
        "Category (police, health, housing, infrastructure, political reform, civil rights, education, transportation)*",
        "Link",
        "In Current Session? (0 = No, 1 = Yes)*",
        "Summary*",
        "Summary Audio",
        "Summary Audio Provider (Default: Sway)",
    ],
    Organizations: [
        "Name*",
        "Icon*",
        "External Bill ID*",
        "External Bill Version",
        "Support (For, Against)*",
        "Summary*",
    ],
};

export const SHEET_HEADER_KEYS = {
    Locale: ["city", "region", "regionCode", "country", "districts", "icon"],
    Legislators: [
        "title",
        "firstName",
        "lastName",
        "externalId",
        "inOffice",
        "party",
        "district",
        "phone",
        "email",
        "twitter",
        "photoURL",
        "link",
        "street",
        "street2",
        "zip"
    ],
    LegislatorVotes: [
        "externalBillId",
        "externalBillVersion",
        "externalLegislatorId",
        "legislatorSupport",
    ],
    Bills: [
        "title",
        "externalId",
        "externalVersion",
        "chamber",
        "status",
        "sponsorExternalId",
        "category",
        "link",
        "isActive",
        "summary",
        "summaryAudio",
        "summaryAudioProvider",
        "votedate",
    ],
    Organizations: [
        "name",
        "icon",
        "externalBillId",
        "externalBillVersion",
        "support",
        "summary",
    ],
};
