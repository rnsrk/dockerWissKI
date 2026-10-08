# OpenGDB patches

Patches against [FAU-CDI/open_gdb](https://github.com/FAU-CDI/open_gdb) (the `opengdb` submodule). `docker compose build authproxy` applies every `*.patch` in this directory on top of the unchanged upstream authproxy image (see `Dockerfile` here and the `authproxy` / `authproxy-upstream` services in `docker-compose.yml`).

| Patch | Status |
| --- | --- |
| `0001-keep-django-repository-when-rdf4j-put-is-not-204.patch` | Not yet sent upstream. Text for the pull request is below. |

## 0001 – a refused RDF4J `PUT` deletes the existing store

### What goes wrong

`Repository.create_remote()` (`authproxy/rdf4j/models.py`) sends `PUT /repositories/<id>` to RDF4J and accepts only HTTP 204. Anything else raises `IntegrityError`. The `post_save` handler (`authproxy/rdf4j/signals/handlers.py`) catches every exception from `create_remote()` and calls `instance.delete()`. The `pre_delete` handler of that delete then calls `delete_remote()`, which sends `DELETE /repositories/<id>` to RDF4J.

So if the `PUT` is refused because the store already exists in RDF4J, authproxy removes its own Django row **and the store with all its data**.

The existing-store case happens whenever authproxy's database is gone but RDF4J's volume is not, for example after recreating only the `authproxy-data` volume and starting the stack again: the client posts `/rest/repositories`, Django creates a new row, RDF4J refuses the second `PUT`, and the cleanup deletes the store.

### Reproduction

Observed with RDF4J `eclipse/rdf4j-workbench:6.1.0-tomcat` and authproxy at upstream commit `f072910`, in an isolated Docker network, once per variant:

1. Start RDF4J and create the store directly: `PUT /rdf4j-server/repositories/default` (Turtle config) returns 204. Add one triple.
2. Start authproxy with an empty database (fresh `/data`).
3. `POST /rest/repositories` with `{"id":"default","title":"x"}` as the superuser.

| | Upstream | With the patch |
| --- | --- | --- |
| Store did not exist before step 3 | HTTP 200, store created | HTTP 200, store created |
| Store existed before step 3 | **HTTP 500; RDF4J reports `Unknown repository: default`, the triple is gone** | HTTP 200; store and triple are still there |

RDF4J 6.1.0 answers the first `PUT` for an id with 204, as the code expects, and a second `PUT` for the same id with `409 REPOSITORY EXISTS: repository already exists: default`. The patch also accepts 400 and 412 as "already exists", as listed in the original commit message; those two were not re-measured here.

### The change

`create_remote()` treats 200, 201 and 204 as created and 400, 409 and 412 as "already there": in both cases `has_remote` is set and the Django row is kept. Any other status still raises, now with the HTTP status and the first 300 characters of the response body in the message.

### Text for the upstream pull request

> **Title:** Do not delete an existing RDF4J repository when `create_remote()` gets a non-204 answer
>
> **Problem.** `Repository.create_remote()` only accepts HTTP 204 from `PUT /repositories/<id>`. For any other answer it raises `IntegrityError`, and `post_repo_save` answers that by calling `instance.delete()`. The `pre_delete` handler then sends `DELETE /repositories/<id>` to RDF4J. If the `PUT` was refused because the repository already exists (for example after the authproxy database was recreated while the RDF4J volume was kept), the existing repository and its data are deleted, and the API call ends in a 500.
>
> **Reproduction.** With RDF4J 6.1.0: create repository `default` directly in RDF4J and add a triple; start authproxy with an empty database; `POST /rest/repositories` with `{"id": "default", "title": "x"}`. Result before this change: HTTP 500 and `Unknown repository: default` in RDF4J. Result after: HTTP 200, repository and triple intact.
>
> **Change.** Accept 200/201/204 as created, treat 400/409/412 as "repository already exists on the remote" and keep the Django row, and raise for everything else with the status code and the start of the response body, which also resolves the existing `TODO: Better error handling`.
>
> **Open question.** RDF4J 6.1.0 answers a duplicate `PUT` with `409 REPOSITORY EXISTS`; we also treat 400 and 412 as "already exists" (from an earlier note, not re-measured). Is that right for all versions you support? A stricter variant could match the `REPOSITORY EXISTS` text in the body instead of the status code.
>
> Alternatively, the cleanup in `post_repo_save` could skip `delete_remote()` when `create_remote()` fails, because the remote was not created by this call. That would be a larger change to the signal handlers, so this patch leaves it out.

### Applying and removing

The patch is generated from the commit `db9417b` of a local checkout (`git format-patch -1`) and applies to upstream `f072910` (`git apply --check -p1` passes). The `Dockerfile` in this directory applies it inside the image with `patch -p2 -d /app`, because the application is `/app` there and `authproxy/` in the repository.

Once upstream contains the fix:

1. `git -C opengdb checkout <upstream commit with the fix>` and commit the new submodule pointer.
2. Delete the patch from this directory. When no patch is left, delete the `Dockerfile` here and the `authproxy-upstream` service, and point `authproxy` back at `build: ./opengdb/authproxy` in `docker-compose.yml`.

If `patch` fails after a submodule update, upstream changed `create_remote()`; check whether the fix is already there before rebasing the patch.
