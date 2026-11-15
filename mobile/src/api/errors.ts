// @lat: [[mobile-api-client-contract#Errors]]
export const GENERIC_ERROR_MESSAGE = "Something went wrong. Please try again.";

export class ApiRequestError extends Error {
    public readonly code: string;
    public readonly details?: Record<string, string[]>;
    public readonly status?: number;

    constructor(code: string, message: string, details?: Record<string, string[]>, status?: number) {
        super(message);
        this.name = "ApiRequestError";
        this.code = code;
        this.details = details;
        this.status = status;
    }
}

export class UnauthorizedError extends ApiRequestError {
    constructor(code: string, message: string, details?: Record<string, string[]>, status?: number) {
        super(code, message, details, status);
        this.name = "UnauthorizedError";
    }
}

export class RateLimitedError extends ApiRequestError {
    public readonly retryAfterSeconds?: number;

    constructor(
        code: string,
        message: string,
        details?: Record<string, string[]>,
        status?: number,
        retryAfterSeconds?: number,
    ) {
        super(code, message, details, status);
        this.name = "RateLimitedError";
        this.retryAfterSeconds = retryAfterSeconds;
    }
}

export class NetworkError extends ApiRequestError {
    constructor(code: string, message: string, details?: Record<string, string[]>, status?: number) {
        super(code, message, details, status);
        this.name = "NetworkError";
    }
}
