// Worker entry point. Only the handler is exported here: the Workers runtime treats every named export
// of the entry module as an entrypoint, so the helpers live in relay.ts.
import { handleRequest, type Env } from "./relay";

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  },
};
