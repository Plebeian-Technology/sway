// @ts-ignore

import emojis from "./emojis.json";

export const getEmojiFromName = (name: string) => {
    if (name.startsWith(":")) {
        return (emojis as Record<string, any>)[name.slice(1, -1)];
    }
    return (emojis as Record<string, any>)[name];
};

export const withEmojis = (string: string | undefined | null): string => {
    const words = (string || "").split(" ");
    const render = [] as string[];
    let i = 0;
    while (i < words.length) {
        const word = words[i];
        if (!word.startsWith(":")) {
            render.push(word);
        } else {
            const e = getEmojiFromName(word);
            if (e) {
                render.push(e);
            } else {
                render.push(word);
            }
        }
        i++;
    }
    return render.join(" ");
};
