FROM cloudron/base:6.0.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee

RUN mkdir -p /app/code/apiserver /app/code/frontend /app/pkg
WORKDIR /app/code

RUN apt-get update && \
    apt-get install -y openjdk-25-jre-headless python3-aiosmtpd && \
    rm -rf /var/cache/apt /var/lib/apt/lists

# renovate: datasource=github-releases depName=DependencyTrack/dependency-track versioning=semver
ARG DEPENDENCY_TRACK_VERSION=5.2.1

# renovate: datasource=github-releases depName=DependencyTrack/frontend versioning=semver
ARG DEPENDENCY_TRACK_FRONTEND_VERSION=5.2.1

RUN curl -sSLf "https://github.com/DependencyTrack/dependency-track/releases/download/${DEPENDENCY_TRACK_VERSION}/dependency-track-apiserver-dist.tar.gz" | tar -xz -C /app/code/apiserver

RUN curl -sSLf -o /tmp/frontend.zip "https://github.com/DependencyTrack/frontend/releases/download/${DEPENDENCY_TRACK_FRONTEND_VERSION}/frontend-dist.zip" && \
    unzip -q /tmp/frontend.zip -d /tmp/frontend && \
    mv /tmp/frontend/dist/* /app/code/frontend/ && \
    rm -rf /tmp/frontend /tmp/frontend.zip && \
    ln -sf /run/dependency-track/config.json /app/code/frontend/static/config.json

RUN rm /etc/nginx/sites-enabled/* && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log
COPY nginx/readonlyrootfs.conf /etc/nginx/conf.d/readonlyrootfs.conf
COPY nginx/dependency-track.conf /etc/nginx/sites-enabled/dependency-track.conf

COPY supervisor/* /etc/supervisor/conf.d/
RUN ln -sf /run/dependency-track/supervisord.log /var/log/supervisor/supervisord.log

COPY env.sh.template start.sh apiserver.sh smtp-relay.py /app/pkg/

CMD [ "/app/pkg/start.sh" ]
