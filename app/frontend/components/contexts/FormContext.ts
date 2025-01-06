import { createContext } from "react";
import { UseInertiaFormProps } from "use-inertia-form";

const FormContext = createContext<UseInertiaFormProps<any>>({} as UseInertiaFormProps<any>);

export default FormContext;
