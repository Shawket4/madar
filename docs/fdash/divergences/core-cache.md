# Core / query cache and prefetch: differences from the web

One line per difference: what the web does, what Flutter does, why.

| Row | Web | Flutter | Why |
|---|---|---|---|
| cache key and the org header | A query's key is its URL and params (Orval). A read whose org comes only from the `X-Org-Id` header (`listPaymentMethods()` and other paramless reads; the server honours the header for platform admins) keeps the same key across an org switch, so the previous org's data is shown for up to 30 s (`staleTime`), then refetched. | Every cached read (`ref.webCache()`) also depends on the org in scope: a platform admin's org switch refetches it, never showing another org's data. Branch scope stays in the keys only, as on the web (the server reads `X-Branch-Id` only as the analytics assistant's default). | Another org's data on screen is a web bug (SPEC 6.3). Fix to port to the web: put the scope org in those queries' keys. |
| timers | `gcTime` is a timer per query. | An unwatched read is swept once older than 5 min whenever any read is built or let go (no timer). | Platform: a pending timer fails every widget test; memory is still bounded by use. |
