import { InertiaFormProps } from "@inertiajs/react";
import { createContext } from "react";

// @lat: [[sway-form-context-typing#Why SwayFormContext is untyped, narrowed per caller]]
const SwayFormContext = createContext<InertiaFormProps<any> | undefined>(undefined);

export default SwayFormContext;
