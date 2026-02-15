Patterns to follow when building with inertia:

1. Do not use useEffect hooks to load initial data for a component. Instead, load in props for the component via inertia.render.

2. When sending data to the server via a POST, PUT or PATCH (PUT is preferred) use Inertia's useForm hook or the Inertia Form component.

3. Inertia receives form data as JSON. Use methods from JsonUtils to parse the JSON string and JsonKeys to extract values from keys.

4. Backend POST and PUT routes that accept form data as JSON should redirect back to the endpoint that originally rendered the Inertia page. The resource that handles the re-direction can convert any query params into props and additionally load any new data from the database before rendering the inertia page that it is responsible for.

5. Simple state such as booleans, strings, numbers and lists of strings or numbers should be tracked through inertia props and url query parameters. For example, the open/close state of a modal. When a user opens a modal inertia's router.get method is called and the state of the modal is set as a query param. The server receives the modal state query param and returns it as props. This removes the need for a useState hook to track the modal state. If using a POST or PUT request, parameters from the request body can be returned to the inertia component via props.

6. Within nested JSX props can be accessed using inertia's usePage() hook. Props do not need to be passed to nested components. https://inertiajs.com/docs/v2/advanced/typescript#page-props.

7. Use Material UI components and styling.
