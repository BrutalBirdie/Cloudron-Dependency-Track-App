#!/bin/bash

set -eu

mkdir -p /run/nginx /run/dependency-track

if [[ ! -f /app/data/env.sh ]]; then
    echo "==> Copying default configuration"
    cp /app/pkg/env.sh.template /app/data/env.sh
fi

export JAVA_OPTIONS="-XX:+UseG1GC -XX:+UseStringDeduplication -XX:+UseCompactObjectHeaders -XX:MaxGCPauseMillis=250 -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"
# the postgresql addon is shared by all apps, upstream defaults are 30 / 15
export DT_DATASOURCE_POOL_MAX_SIZE=15
export DT_DATASOURCE_POOL_MIN_IDLE=3
export DT_TELEMETRY_SUBMISSION_DEFAULT_ENABLED=false

source /app/data/env.sh

# keys/secret-management-kek.json encrypts secrets stored in the database and must be backed up with it
export DT_DATA_DIRECTORY=/app/data
# loopback is blocked by default, the email publisher must reach smtp-relay.py
export DT_OUTBOUND_ALLOWED_DESTINATIONS="external,127.0.0.1/32"
export DT_DATASOURCE_URL="jdbc:postgresql://${CLOUDRON_POSTGRESQL_HOST}:${CLOUDRON_POSTGRESQL_PORT}/${CLOUDRON_POSTGRESQL_DATABASE}"
export DT_DATASOURCE_USERNAME="${CLOUDRON_POSTGRESQL_USERNAME}"
export DT_DATASOURCE_PASSWORD="${CLOUDRON_POSTGRESQL_PASSWORD}"

# the frontend runs the OIDC code flow in the browser, so it needs the public (PKCE) client
oidc_issuer=""
oidc_client_id=""
if [[ -n "${CLOUDRON_OIDC_PUBLIC_CLIENT_ID:-}" ]]; then
    oidc_issuer="${CLOUDRON_OIDC_ISSUER}"
    oidc_client_id="${CLOUDRON_OIDC_PUBLIC_CLIENT_ID}"

    export DT_OIDC_ENABLED=true
    export DT_OIDC_ISSUER="${oidc_issuer}"
    export DT_OIDC_CLIENT_ID="${oidc_client_id}"
    export DT_OIDC_USERNAME_CLAIM=preferred_username
    export DT_OIDC_USER_PROVISIONING=true
    export DT_OIDC_TEAM_SYNCHRONIZATION=true
    export DT_OIDC_TEAMS_CLAIM=groups
fi

cat > /run/dependency-track/config.json <<EOF
{
  "API_BASE_URL": "",
  "API_WITH_CREDENTIALS": "",
  "FEATURE_FLAGS": {
    "GLOBAL_POLICY_VIOLATION_AUDIT": true,
    "GLOBAL_VULNERABILITY_AUDIT": true
  },
  "OIDC_ISSUER": "${oidc_issuer}",
  "OIDC_CLIENT_ID": "${oidc_client_id}",
  "OIDC_SCOPE": "openid profile email groups",
  "OIDC_FLOW": "code",
  "OIDC_LOGIN_BUTTON_TEXT": "${CLOUDRON_OIDC_PROVIDER_NAME:-Cloudron}"
}
EOF

chown -R cloudron:cloudron /app/data /run/dependency-track

echo "==> Running database migrations"
DT_INIT_TASKS_EXIT_AFTER_COMPLETION=true gosu cloudron:cloudron /app/pkg/apiserver.sh

if [[ -n "${CLOUDRON_MAIL_SMTP_SERVER:-}" ]]; then
    echo "==> Configuring email"
    email_config=$(printf '{"enabled": true, "host": "127.0.0.1", "port": 2525, "sslEnabled": false, "startTlsEnabled": false, "senderAddress": "%s"}' "${CLOUDRON_MAIL_FROM}")
    PGPASSWORD="${CLOUDRON_POSTGRESQL_PASSWORD}" psql -q -v ON_ERROR_STOP=1 -v config="${email_config}" \
        -h "${CLOUDRON_POSTGRESQL_HOST}" -p "${CLOUDRON_POSTGRESQL_PORT}" -U "${CLOUDRON_POSTGRESQL_USERNAME}" -d "${CLOUDRON_POSTGRESQL_DATABASE}" <<'EOF'
INSERT INTO "EXTENSION_RUNTIME_CONFIG" ("EXTENSION_POINT", "EXTENSION", "CONFIG", "CREATED_AT")
VALUES ('notification-publisher', 'email', CAST(:'config' AS JSONB), NOW())
ON CONFLICT ("EXTENSION_POINT", "EXTENSION") DO UPDATE SET "CONFIG" = EXCLUDED."CONFIG", "UPDATED_AT" = NOW();
EOF
fi

echo "==> Starting Dependency-Track"
exec /usr/bin/supervisord --configuration /etc/supervisor/supervisord.conf --nodaemon -i DependencyTrack
