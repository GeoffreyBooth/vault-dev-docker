#!/usr/bin/dumb-init /bin/sh
rm -f /opt/healthcheck

#copypasta from upstream docker-entrypoint.sh

# VAULT_CONFIG_DIR isn't exposed as a volume but you can compose additional
# config files in there if you use this image as a base, or use
# VAULT_LOCAL_CONFIG below.
VAULT_CONFIG_DIR=/vault/config

VAULT_SECRETS_FILE=${VAULT_SECRETS_FILE:-"/opt/secrets.json"}
VAULT_APP_ID_FILE=${VAULT_APP_ID_FILE:-"/opt/app-id.json"}
VAULT_POLICIES_FILE=${VAULT_POLICIES_FILE:-"/opt/policies.json"}

# If environment variables are set containing the above data, and the files
# are missing, write the environment variables data out to the files
if [ -n "${VAULT_SECRETS+1}" ] && [[ ! -f "$VAULT_SECRETS_FILE" ]]; then
  echo "$VAULT_SECRETS" >> "$VAULT_SECRETS_FILE"
fi
if [ -n "${VAULT_APP_ID+1}" ] && [[ ! -f "$VAULT_APP_ID_FILE" ]]; then
  echo "$VAULT_APP_ID" >> "$VAULT_APP_ID_FILE"
fi
if [ -n "${VAULT_POLICIES+1}" ] && [[ ! -f "$VAULT_POLICIES_FILE" ]]; then
  echo "$VAULT_POLICIES" >> "$VAULT_POLICIES_FILE"
fi

# You can also set the VAULT_LOCAL_CONFIG environment variable to pass some
# Vault configuration JSON without having to bind any volumes.
if [ -n "$VAULT_LOCAL_CONFIG" ]; then
  echo "$VAULT_LOCAL_CONFIG" > "$VAULT_CONFIG_DIR/local.json"
fi

vault server \
  -config="$VAULT_CONFIG_DIR" \
  -dev-root-token-id="${VAULT_DEV_ROOT_TOKEN_ID:-root}" \
  -dev-listen-address="${VAULT_DEV_LISTEN_ADDRESS:-"0.0.0.0:8200"}" \
  -dev "$@" &

# end copypasta

# Poll until Vault is ready
for i in {1..10}; do (vault status) > /dev/null 2>&1 && break || if [ "$i" -lt 11 ]; then sleep $((i * 2)); else echo 'Timeout waiting for Vault to be ready' && exit 1; fi; done

# use the v1 version of the API if requested; https://stackoverflow.com/a/49903604/223225
if [ -n "$VAULT_USE_V1_API" ]; then
  vault secrets disable "${VAULT_USE_V1_API}"
  vault secrets enable -version=1 -path="${VAULT_USE_V1_API}" kv
fi

# parse JSON array, populate Vault
if [[ -f "$VAULT_SECRETS_FILE" ]]; then
  for path in $(jq -r 'keys[]' < "$VAULT_SECRETS_FILE"); do
    value=$(jq -rj ".\"${path}\"" < "$VAULT_SECRETS_FILE")
    type=$(jq -rj ".\"${path}\" | \"\(. | type)\"" < "$VAULT_SECRETS_FILE")
    echo "writing ${type} value to ${path}"
    if [ $type = 'object' ] || [ $type = 'array' ]; then
      echo "$value" | vault write "${path}" -
    else
      echo "$value" | vault write "${path}" value=-
    fi
  done
else
  echo "$VAULT_SECRETS_FILE not found, skipping"
fi

# Optionally install the app id backend.
if [ -n "$VAULT_USE_APP_ID" ]; then
  vault auth-enable app-id
  if [[ -f "$VAULT_APP_ID_FILE" ]]; then
    for appID in $(jq -rc '.[]' < "$VAULT_APP_ID_FILE"); do
      name=$(echo "$appID" | jq -r ".name")
      policy=$(echo "$appID" | jq -r ".policy")
      echo "creating AppID policy with app ID $name for policy $policy"
      vault write auth/app-id/map/app-id/$name value=$policy display_name=$name
      for userID in $(echo "$appID" | jq -r ".user_ids[]"); do
        name=$(echo "$appID" | jq -r ".name")
        echo "...creating user ID $userID for AppID $name"
        vault write auth/app-id/map/user-id/${userID} value=${name}
      done
    done
  else
    echo "$VAULT_APP_ID_FILE not found, skipping"
  fi
fi

# Create any policies.
if [[ -f "$VAULT_POLICIES_FILE" ]]; then
  for policy in $(jq -r 'keys[]' < "$VAULT_POLICIES_FILE"); do
    jq -rj ".\"${policy}\"" < "$VAULT_POLICIES_FILE" > /tmp/value
    echo "creating vault policy $policy"
    vault policy-write "${policy}" /tmp/value
    rm -f /tmp/value
  done
else
  echo "$VAULT_POLICIES_FILE not found, skipping"
fi

# docker healthcheck
touch /opt/healthcheck

echo 'Vault server is listening...'

# block forever
tail -f /dev/null
