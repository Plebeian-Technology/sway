import { isPlainObject } from "lodash";
import { sway } from "sway";

export const isHTTP = (str: any) => typeof str === "string" && str.startsWith("http");

export const isBlobString = (str: any) => typeof str === "string" && str.startsWith("blob:http");

export const isFailedRequest = (
    result: unknown,
): boolean => {
    return !!(
        result &&
        isPlainObject(result) &&
        "success" in (result as sway.IValidationResult) &&
        !(result as sway.IValidationResult).success
    );
};