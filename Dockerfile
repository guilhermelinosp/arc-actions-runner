# hadolint ignore=DL3006
ARG TRIVY_VERSION=0.72.0
ARG COSIGN_VERSION=3.1.1
ARG GH_VERSION=2.96.0
ARG CRANE_VERSION=0.21.7
ARG BUILDX_VERSION=0.35.0
ARG VAULT_VERSION=1.20.3
ARG YQ_VERSION=4.53.3
ARG RUNNER_VERSION=2.335.1

# hadolint ignore=DL3006
FROM summerwind/actions-runner:v${RUNNER_VERSION}-ubuntu-24.04 AS base

LABEL org.opencontainers.image.source="https://github.com/guilhermelinosp/arc-runner"
LABEL org.opencontainers.image.description="Custom ARC runner with buildx, trivy, cosign, gh, crane, vault, mc"
LABEL org.opencontainers.image.version="${RUNNER_VERSION}"

USER root

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    unzip \
    gnupg \
    wget \
    tar \
    gzip \
    bash \
    openssh-client \
    pass \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /usr/libexec/docker/cli-plugins /opt/tools/bin

FROM base AS yq

ARG YQ_VERSION

RUN curl -fsSLo /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" && \
    chmod +x /usr/local/bin/yq

FROM base AS buildx

ARG BUILDX_VERSION

RUN curl -fsSLO "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-amd64" && \
    mv "buildx-v${BUILDX_VERSION}.linux-amd64" /usr/libexec/docker/cli-plugins/docker-buildx && \
    chmod +x /usr/libexec/docker/cli-plugins/docker-buildx

FROM base AS trivy

ARG TRIVY_VERSION

RUN curl -fsSLO "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" && \
    tar -xzf "trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" -C /usr/local/bin trivy && \
    chmod +x /usr/local/bin/trivy && \
    rm -f "trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"

FROM base AS cosign

ARG COSIGN_VERSION

RUN curl -fsSLO "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64" && \
    install -m 755 cosign-linux-amd64 /usr/local/bin/cosign && \
    rm -f cosign-linux-amd64

FROM base AS gh-cli

ARG GH_VERSION

RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz && \
    tar -xzf /tmp/gh.tar.gz -C /tmp && \
    install -m 755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh && \
    rm -rf /tmp/gh*

FROM base AS crane

ARG CRANE_VERSION

RUN curl -fsSLO "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" && \
    tar -xzf "go-containerregistry_Linux_x86_64.tar.gz" -C /tmp && \
    install -m 755 /tmp/crane /usr/local/bin/crane && \
    rm -rf /tmp/go-containerregistry* /tmp/crane

FROM base AS vault

ARG VAULT_VERSION

RUN curl -fsSLO "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" && \
    unzip -j "vault_${VAULT_VERSION}_linux_amd64.zip" -d /usr/local/bin vault && \
    chmod +x /usr/local/bin/vault && \
    rm -f "vault_${VAULT_VERSION}_linux_amd64.zip"

FROM base AS minio

RUN curl -fsSLo /usr/local/bin/mc \
    "https://dl.min.io/client/mc/release/linux-amd64/mc" && \
    chmod +x /usr/local/bin/mc

FROM base AS final

LABEL org.opencontainers.image.base.name="summerwind/actions-runner:v${RUNNER_VERSION}-ubuntu-24.04"

COPY --from=yq /usr/local/bin/yq /usr/local/bin/yq
COPY --from=buildx /usr/libexec/docker/cli-plugins/docker-buildx /usr/libexec/docker/cli-plugins/docker-buildx
COPY --from=trivy /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=cosign /usr/local/bin/cosign /usr/local/bin/cosign
COPY --from=gh-cli /usr/local/bin/gh /usr/local/bin/gh
COPY --from=crane /usr/local/bin/crane /usr/local/bin/crane
COPY --from=vault /usr/local/bin/vault /usr/local/bin/vault
COPY --from=minio /usr/local/bin/mc /usr/local/bin/mc

# Credential helper para docker login (evita warning de token em texto puro)
RUN mkdir -p /home/runner/.gnupg /home/runner/.docker && \
    chmod 700 /home/runner/.gnupg && \
    echo '{"credsStore":"pass"}' > /home/runner/.docker/config.json && \
    chown -R runner:runner /home/runner/.gnupg /home/runner/.docker && \
    chown -R runner:runner /home/runner

# Credential helper: rngd + gpg + pass (como runner)
RUN apt-get install -y rng-tools5
USER runner
RUN rngd -r /dev/urandom && \
    gpg --batch --passphrase '' --quick-gen-key 'runner@local' default default && \
    pass init runner@local && \
    killall rngd 2>/dev/null
USER root
RUN apt-get purge -y rng-tools5 && apt-get autoremove -y

ENV RUNNER_WORK_DIRECTORY=/home/runner/_work
ENV RUNNER_TEMP=/home/runner/_temp
ENV RUNNER_TOOL_CACHE=/home/runner/_tool
ENV PATH="${PATH}:/opt/tools/bin"

WORKDIR /home/runner
USER runner
