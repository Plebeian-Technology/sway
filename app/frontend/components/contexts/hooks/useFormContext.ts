import FormContext from "app/frontend/components/contexts/FormContext";
import { useContext } from "react";
import { UseInertiaFormProps } from "use-inertia-form";

export const useFormContext = <T>() => useContext<UseInertiaFormProps<T>>(FormContext);
