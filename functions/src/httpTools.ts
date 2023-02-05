/** @format */

export interface ISwayResponse {
    success: boolean;
    message: string;
    data: Record<string, unknown>;
}

export const response = (success: boolean, message: string, data: any = {}): ISwayResponse => {
    return {
        success,
        message,
        data,
    };
};
