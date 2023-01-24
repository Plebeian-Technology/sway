export const PROPUBLICA_HEADERS = {
    Accept: "application/json",
    "Content-Type": "application/json",
    "X-API-Key": process.env.PROPUBLICA_API_KEY || "",
};

export const PROPUBLICA_API_BASE_ROUTE = "https://api.propublica.org/congress/v1";

export const US_GOVERNMENT_LEGISLATORS_URL =
    "https://theunitedstates.io/congress-legislators/legislators-current.json";
export const US_GOVERNMENT_LEGISLATORS_SOCIALS_URL =
    "https://theunitedstates.io/congress-legislators/legislators-social-media.json";
