import produce, { Draft, freeze, nothing } from "immer";
import { useCallback, useState } from "react";

export type Reducer<S = any, A = any> = (
    draftState: Draft<S>,
    action: A,
) => void | (S extends undefined ? typeof nothing : S);
export type DraftFunction<S> = (draft: Draft<S>) => void;
export type Updater<S> = (arg: S | DraftFunction<S>) => void;
export type ImmerHook<S> = [S, Updater<S>];

export function useImmer<S = any>(initialValue: S | (() => S)): ImmerHook<S> {
    const [val, updateValue] = useState(() =>
        freeze(initialValue instanceof Function ? initialValue() : initialValue, true),
    );
    return [
        val,
        useCallback((updater) => {
            if (updater instanceof Function) updateValue(produce(updater));
            else updateValue(freeze(updater));
        }, []),
    ];
}
