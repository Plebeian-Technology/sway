// @lat: [[websocket-token-log-scrubbing#consumer.ts's single shared consumer]]
import { createConsumer, Consumer } from "@rails/actioncable";

import { API_BASE_URL } from "../constants/api";

let _consumer: Consumer | null = null;
let _consumerToken: string | null = null;
let _authStrategy: "header" | "query" | null = null;

// @lat: [[websocket-token-log-scrubbing#Why consumer.ts puts the token on the query string instead of a header]]
function buildCableUrl(token: string | null): string {
    const wsBase = API_BASE_URL.replace(/^http/, "ws");
    if (!token) return `${wsBase}/cable`;
    return `${wsBase}/cable?token=${encodeURIComponent(token)}`;
}

export async function getConsumer(token: string | null): Promise<Consumer> {
    if (_consumer && token !== _consumerToken) {
        destroyConsumer();
    }
    if (_consumer) return _consumer;
    const url = buildCableUrl(token);
    _consumer = createConsumer(url);
    _consumerToken = token;
    _authStrategy = token ? "query" : null;
    return _consumer;
}

export function currentAuthStrategy(): "header" | "query" | null {
    return _authStrategy;
}

export function destroyConsumer(): void {
    try {
        _consumer?.disconnect();
    } catch {}
    _consumer = null;
    _consumerToken = null;
    _authStrategy = null;
}
