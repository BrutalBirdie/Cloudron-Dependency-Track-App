#!/bin/bash
# Smoke test without a Cloudron server: read-only rootfs, Postgres, an SMTP server that requires auth.
# Usage: test/smoke/run.sh   (needs Docker)  IMAGE=<tag> skips the build, KEEP=1 keeps the containers

set -eu

cd "$(dirname "$0")"
readonly root=$(cd ../.. && pwd)
readonly img=${IMAGE:-dtrack:smoke}
readonly net=dtsmoke
readonly app=dtsmoke-app
readonly db=dtsmoke-db
readonly smtp=dtsmoke-smtp
readonly api=http://127.0.0.1:18000/api
readonly admin_password=Smoke-Test-123456
failures=0

cleanup() {
    [[ -n "${ARTIFACTS:-}" ]] && { mkdir -p "${ARTIFACTS}"; docker logs "${app}" > "${ARTIFACTS}/app.log" 2>&1 || true; docker logs "${smtp}" > "${ARTIFACTS}/smtp.log" 2>&1 || true; }
    [[ -n "${KEEP:-}" ]] && return
    docker rm -f "${app}" "${db}" "${smtp}" >/dev/null 2>&1 || true
    docker volume rm dtsmoke-data >/dev/null 2>&1 || true
    docker network rm "${net}" >/dev/null 2>&1 || true
}
cleanup
trap cleanup EXIT

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1 :: $2"; failures=$((failures + 1)); }
expect() { if [[ "$3" =~ $2 ]]; then pass "$1"; else fail "$1" "${3:0:300}"; fi; }

wait_for() { # wait_for <seconds> <command...>
    local deadline=$((SECONDS + $1)); shift
    until "$@" >/dev/null 2>&1; do
        (( SECONDS > deadline )) && return 1
        sleep 2
    done
}

[[ -z "${IMAGE:-}" ]] && docker build -t "${img}" "${root}"

docker network create "${net}" >/dev/null
docker run -d --name "${db}" --network "${net}" -e POSTGRES_DB=db -e POSTGRES_USER=user -e POSTGRES_PASSWORD=pass postgres:16-alpine >/dev/null
docker run -d --name "${smtp}" --network "${net}" -v "${PWD}/smtp-sink.py:/smtp-sink.py:ro" python:3.13-slim \
    sh -c "pip install -q --root-user-action=ignore aiosmtpd==1.4.6 && python -u /smtp-sink.py" >/dev/null
wait_for 60 docker exec "${db}" pg_isready -U user -d db
wait_for 120 docker exec "${smtp}" python -c "import socket; socket.create_connection(('127.0.0.1', 2525))"

docker run -d --name "${app}" --network "${net}" --read-only --tmpfs /run:exec --tmpfs /tmp:exec -v dtsmoke-data:/app/data -m 2g -p 127.0.0.1:18000:8000 \
    -e CLOUDRON_POSTGRESQL_HOST="${db}" -e CLOUDRON_POSTGRESQL_PORT=5432 -e CLOUDRON_POSTGRESQL_DATABASE=db -e CLOUDRON_POSTGRESQL_USERNAME=user -e CLOUDRON_POSTGRESQL_PASSWORD=pass \
    -e CLOUDRON_MAIL_SMTP_SERVER="${smtp}" -e CLOUDRON_MAIL_SMTP_PORT=2525 -e CLOUDRON_MAIL_SMTP_USERNAME=u -e CLOUDRON_MAIL_SMTP_PASSWORD=p -e CLOUDRON_MAIL_FROM=dtrack@example.com \
    "${img}" >/dev/null

if ! wait_for 180 curl -sf ${api}/version; then
    fail "health" "app did not become healthy"
    exit 1
fi
pass "health"

expect "frontend" "Dependency-Track" "$(curl -s http://127.0.0.1:18000/)"
expect "api version" '"application":"Dependency-Track"' "$(curl -s ${api}/version)"
expect "oidc disabled without addon" '"OIDC_ISSUER": ""' "$(curl -s http://127.0.0.1:18000/static/config.json)"

expect "change admin password" "^200$" "$(curl -s -o /dev/null -w '%{http_code}' -X POST ${api}/v1/user/forceChangePassword -d "username=admin&password=admin&newPassword=${admin_password}&confirmPassword=${admin_password}")"
token=$(curl -s -X POST ${api}/v1/user/login -d "username=admin&password=${admin_password}")
auth="Authorization: Bearer ${token}"

expect "email configured" '"host":"127.0.0.1".*"senderAddress":"dtrack@example.com"' "$(curl -s -H "${auth}" ${api}/v2/extension-points/notification-publisher/extensions/email/config)"

publisher=$(curl -s -H "${auth}" ${api}/v1/notification/publisher | yq -p json '.[] | select(.extensionName == "email") | .uuid')
rule=$(curl -s -X PUT -H "${auth}" -H 'Content-Type: application/json' ${api}/v1/notification/rule \
    -d "{\"name\": \"smoke\", \"level\": \"INFORMATIONAL\", \"scope\": \"SYSTEM\", \"publisher\": {\"uuid\": \"${publisher}\"}}")
rule=$(echo "${rule}" | yq -p json -o json '.notifyOn = ["USER_CREATED"] | .publisherConfig = "{\"subjectPrefix\": \"[Dependency-Track]\", \"recipientAddresses\": [\"someone@example.com\"]}"')
curl -s -o /dev/null -X POST -H "${auth}" -H 'Content-Type: application/json' ${api}/v1/notification/rule -d "${rule}"
curl -s -o /dev/null -X POST -H "${auth}" "${api}/v1/notification/publisher/test/$(echo "${rule}" | yq -p json '.uuid')"

if wait_for 60 sh -c "docker logs ${smtp} 2>&1 | grep -q '^MAIL'"; then
    expect "email sent with auth" "MAIL from dtrack@example.com to \['someone@example.com'\] authed True" "$(docker logs ${smtp} 2>&1)"
else
    fail "email sent with auth" "no mail received"
fi

docker restart "${app}" >/dev/null
if wait_for 180 curl -sf ${api}/version; then pass "restart"; else fail "restart" "app did not become healthy"; fi
expect "login after restart" "^200$" "$(curl -s -o /dev/null -w '%{http_code}' -X POST ${api}/v1/user/login -d "username=admin&password=${admin_password}")"

echo "==> ${failures} failures"
exit $(( failures > 0 ))
