import { Landmark, Megaphone, Vote } from "lucide-react";

import PasskeyPanel from "app/frontend/components/auth/PasskeyPanel";
import { Card, CardContent } from "app/frontend/components/ui/card";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

const heroItems = [
    {
        title: "Cut through the noise",
        description: "Vote on the issues that matter, don't get bogged down by meaningless legislation.",
        Icon: Landmark,
    },
    {
        title: "Cast your vote",
        description: "Keep support and opposition obvious, fast, and readable on the first screen.",
        Icon: Vote,
    },
    {
        title: "Reach the right people",
        description: "Use Sway to move from awareness to action without losing your place in the flow.",
        Icon: Megaphone,
    },
];

// @lat: [[home-layout-theme-concepts#DefaultHomeLayout]]
const HomeHero: React.FC = () => {
    return (
        <section className="grid gap-6 lg:grid-cols-12 lg:items-start lg:gap-x-10 lg:gap-y-6">
            <div className="space-y-4 lg:col-span-7">
                <h1 className="text-balance text-3xl font-black leading-tight tracking-tight text-foreground sm:text-4xl lg:text-5xl">
                    {PARITY_COPY.auth.hero.headline}
                </h1>
                <p className="max-w-xl text-pretty text-base leading-relaxed text-muted-foreground sm:text-lg">
                    {PARITY_COPY.auth.hero.paragraph}
                </p>
            </div>

            <div className="lg:col-span-5 lg:row-span-2">
                <PasskeyPanel />
            </div>

            <div className="grid gap-3 lg:col-span-7">
                {heroItems.map(({ title, description, Icon }) => (
                    <Card key={title} className="bg-card py-4">
                        <CardContent className="flex items-start gap-4 px-4 sm:px-5">
                            <span
                                className="flex size-10 shrink-0 items-center justify-center rounded-lg border-neo border-border-soft bg-surface-3 text-primary"
                                aria-hidden="true"
                            >
                                <Icon className="size-5" />
                            </span>
                            <div className="min-w-0 space-y-1">
                                <h2 className="text-base font-semibold leading-snug text-foreground">{title}</h2>
                                <p className="text-sm leading-relaxed text-muted-foreground">{description}</p>
                            </div>
                        </CardContent>
                    </Card>
                ))}
            </div>
        </section>
    );
};

export default HomeHero;
