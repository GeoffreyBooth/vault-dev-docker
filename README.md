# Vault Development Docker Image

Docker image based on upstream official Vault image which allows pre-populating with secrets for local development/testing. **DO NOT USE FOR PRODUCTION PURPOSES.**

Secrets
-------

On startup, Vault will read secrets from a file or environment variable and write them into the generic secret backend.

If you have your secrets saved in a JSON file, you can pass them in as a volume, e.g. `--volume $PWD/localhost-secrets.json:/opt/secrets.json`. Vault looks for secrets at the path defined by `$VAULT_SECRETS_FILE`, which by default is `/opt/secrets.json`. Override that variable to change where Vault should load the secrets from.

You can also pass secrets in via an environment variable, `$VAULT_SECRETS`. This should be a JSON string. If both the secrets file and the environment variable are present, the file takes precedence.

The contents of the JSON file or environment variable is an object associating a path with value, as follows:

```json
{
  "secret/foo/bar": "baz",
  "secret/something/else": {
    "someKey": "someValue",
    "anotherKey": "anotherValue"
  }
}
```

If you see errors in your Vault client about `Invalid path for a versioned K/V secrets engine`, set the `vault-dev` container `VAULT_USE_V1_API` environment variable to `secret`. This [recreates](https://stackoverflow.com/a/49903604/223225) the `/secret` engine using v1 of the Vault API. Here’s example usage in `docker-compose.yml`:

```yaml
  vault:
    image: geoffreybooth/vault-dev
    volumes:
      - ./secrets.json:/opt/secrets.json
    environment:
      VAULT_USE_V1_API: secret
    ports:
      - '8200:8200'
```

Backends
--------

The following backends can be enabled by setting the appropriate environment variable to `1`:

- App ID: `$VAULT_USE_APP_ID`

App ID
------

If the app ID backend is enabled, app ID profiles can be created by setting the file at `/opt/app-id.json` (override path with `$VAULT_APP_ID_FILE`, or set contents to `$VAULT_APP_ID` environment variable as with `$VAULT_SECRETS` above):

```json
[
  {
    "name": "app-id-1",
    "policy": "root",
    "user_ids": [
      "asdf",
      "qwerty"
    ]
  },
  {
    "name": "app-id-2",
    "policy": "root",
    "user_ids": [
      "mary",
      "fred"
    ]
  }
]
```

Policies
--------

Policies can be created by specifying the file at `/opt/policies.json` (override path with `$VAULT_POLICIES_FILE`, or set contents to `$VAULT_POLICIES` environment variable as with `$VAULT_SECRETS` above) as follows:

```json
{
  "policy1": "path \"secret/*\" { policy = \"write\" }"
}
```

Healthcheck
-----------
The native Docker healthcheck will return healthy when all configured secrets have been written.

Authentication
--------------

The upstream vault image is mostly unmodified so it runs Vault in development by
default (no auth necessary) and also respects the environment variable `VAULT_DEV_ROOT_TOKEN_ID`.

See https://hub.docker.com/_/vault/ for details.

Docker Registry
---------------

https://hub.docker.com/r/geoffreybooth/vault-dev/

Source
------

Forked from [https://github.com/dollarshaveclub/vault-dev-docker](https://github.com/dollarshaveclub/vault-dev-docker)
