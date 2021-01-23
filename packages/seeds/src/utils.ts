import { random } from "lodash";

export const IS_DEVELOPMENT = process.env.NODE_ENV === "development";
export const isTest = process.env.NODE_ENV === "test";

export const SEED_UID = `demo-user-${random(1, 100000)}`;
