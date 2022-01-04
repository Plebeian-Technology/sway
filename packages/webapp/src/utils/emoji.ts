// @ts-ignore

import emojis from "./emojis.json";

export const getEmojiFromName = (name: string) => {
    if (name.charAt(0) === ":") {
        return emojis[name.slice(1, -1)];
    }
    return emojis[name];
};
