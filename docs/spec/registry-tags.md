# Registry Tag Listing (T2.16)

> Status: v0.1, implemented by `registry/tags.emo` (route + pagination) and
> `registry/db.emo` (`list_tags_page`). Tests: `test/registry_tags.emo`
> (handler with a fake page source) and the compiled `db_selftest` (the real
> SQL page query).

## Route

`GET /v2/<name>/tags/list`

- Success answers `{"name":"<name>","tags":[…]}` with the tags in lexical
  order (`ORDER BY tag`), `Content-Type: application/json`.
- Pagination: `n` is the maximum page size, `last` is a tag **value** the
  page starts after (exclusive). A missing `last` starts at the first tag.
- A full page followed by more tags carries
  `Link: </v2/<name>/tags/list?n=<n>&last=<last of page>>; rel="next"`
  (a relative URI-reference, resolved against the request URL per RFC 5988).
  The last page — and any listing without `n`, which returns everything —
  carries no Link.
- `n=0` answers an empty list with no Link. A non-numeric or negative `n` is
  `400 TAG_INVALID`. A repository that does not exist is
  `404 NAME_UNKNOWN`; an existing repository without tags answers an empty
  list. Other methods answer 405 with `Allow: GET`.
- The query reads the live table, so a tag update is visible on the next
  page request by construction.
- Authentication rides the same gate: the listing needs
  `repository:<name>:pull` ([registry-auth.md](registry-auth.md)).

## Tests

`test/registry_tags.emo` covers: route shapes, the full listing, the empty
repository, the missing repository (404), page boundaries with the Link
header (format and exclusivity), the tail page without Link, `n=0`, invalid
`n`, methods, and the auth-enabled 401/pass legs. The compiled `db_selftest`
pins the SQL semantics: lexical order, exclusive `last`, the more flag, and
the empty page past the end.
