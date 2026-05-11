ARG TRIVY_VERSION=0.70.0
ARG COSIGN_VERSION=3.0.6
ARG GH_VERSION=2.90.0
ARG CRANE_VERSION=0.21.5
ARG BUILDX_VERSION=0.33.0
FROM summerwind/actions-runner:latest AS base

USER root
ENV DEBIAN_FRONTEND=noninteractive TERM=xterm

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git jq unzip gnupg wget yq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /usr/libexec/docker/cli-plugins /opt/tools/bin
FROM base AS buildx

ARG BUILDX_VERSION

RUN --mount=type=cache,target=/tmp/buildx-cache \
    curl -fsSLO "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-amd64" && \
    mv buildx-v${BUILDX_VERSION}.linux-amd64 /usr/libexec/docker/cli-plugins/docker-buildx && \
    chmod +x /usr/libexec/docker/cli-plugins/docker-buildx
FROM base AS trivy

ARG TRIVY_VERSION

RUN curl -fsSLO "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" && \
    tar -xzf trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz -C /usr/local/bin trivy && \
    chmod +x /usr/local/bin/trivy && \
    rm -f trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz

FROM base AS cosign

ARG COSIGN_VERSION

RUN curl -fsSLO "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64" && \
    install -m 755 cosign-linux-amd64 /usr/local/bin/cosign && \
    rm -f cosign-linux-amd64

FROM base AS gh-cli

ARG GH_VERSION

RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz && \
    tar -xzf /tmp/gh.tar.gz -C /tmp && \
    install -m 755 /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh /usr/local/bin/gh && \
    rm -rf /tmp/gh*

FROM base AS crane

ARG CRANE_VERSION

RUN curl -fsSLO "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" && \
    tar -xzf go-containerregistry_Linux_x86_64.tar.gz -C /tmp && \
    install -m 755 /tmp/crane /usr/local/bin/crane && \
    rm -rf /tmp/go-containerregistry* /tmp/crane

FROM base AS final

COPY --from=buildx /usr/libexec/docker/cli-plugins/docker-buildx /usr/libexec/docker/cli-plugins/docker-buildx
COPY --from=trivy /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=cosign /usr/local/bin/cosign /usr/local/bin/cosign
COPY --from=gh-cli /usr/local/bin/gh /usr/local/bin/gh
COPY --from=crane /usr/local/bin/crane /usr/local/bin/crane

RUN mkdir -p /home/runner /home/runner/_work /runner/_work && \
    chmod +x \
        /usr/libexec/docker/cli-plugins/docker-buildx \
        /usr/local/bin/trivy \
        /usr/local/bin/cosign \
        /usr/local/bin/gh \
        /usr/local/bin/crane && \
    chown -R runner:docker /home/runner /runner && \
    chmod -R a+rX /usr/local/bin/trivy /usr/local/bin/cosign /usr/local/bin/gh /usr/local/bin/crane /usr/libexec/docker/cli-plugins/docker-buildx
ENV RUNNER_WORK_DIRECTORY=/home/runner/_work
WORKDIR /home/runner
USER runner
