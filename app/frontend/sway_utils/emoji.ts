let EMOJIS = {};

const getEmojiFromName = async (name: string): Promise<string> => {
    const emojis =
        EMOJIS ||
        (await fetch("./emojis.json")
            .then((r) => r.json())
            .then((j) => {
                EMOJIS = j;
                return j;
            })
            .catch((e) => {
                console.error(e);
                return {};
            }));

    if (name.startsWith(":")) {
        return (emojis as Record<string, any>)[name.slice(1, -1)];
    }
    return (emojis as Record<string, any>)[name];
};

export const withEmojis = async (string: string | undefined | null): Promise<string> => {
    const words = (string || "").split(" ");
    const render = [] as string[];
    let i = 0;
    while (i < words.length) {
        const word = words[i];
        if (!word.startsWith(":")) {
            render.push(word);
        } else {
            const e = await getEmojiFromName(word);
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
