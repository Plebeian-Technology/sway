/** @format */

import { sway } from "sway";

// https://stackoverflow.com/questions/41038812/declare-dynamically-added-class-properties-in-typescript
export class Legislator {
    [dyanmicProperty: string]: any;

    constructor(legislator: sway.IBasicLegislator) {
        Object.assign(this, legislator);

        this.full_name = `${this.first_name} ${this.last_name}`;
    }

    static create<T extends typeof Legislator>(
        this: T,
        legislator: sway.IBasicLegislator,
    ) {
        return (
            legislator &&
            (new this(legislator) as InstanceType<T> & sway.ILegislator)
        );
    }
}
