# hadolint ignore=DL3006
ARG RUNNER_VERSION=2.335.1
ARG DOTNET_CHANNEL=LTS
ARG GOLANG_VERSION=1.26.5
ARG YQ_VERSION=4.53.3
ARG TRIVY_VERSION=0.72.0
ARG COSIGN_VERSION=3.1.1
ARG GH_VERSION=2.96.0
ARG CRANE_VERSION=0.21.7
ARG SYFT_VERSION=1.21.0
ARG GRYPE_VERSION=0.92.0
ARG ORAS_VERSION=1.2.2
ARG KUBECTL_VERSION=1.32.0
ARG HELM_VERSION=3.17.2

# hadolint ignore=DL3006,DL3002
FROM summerwind/actions-runner:v${RUNNER_VERSION}-ubuntu-24.04 AS base

LABEL org.opencontainers.image.source="https://github.com/guilhermelinosp/arc-runner"
LABEL org.opencontainers.image.description="Custom ARC runner with podman, buildah, skopeo, syft, grype, trivy, cosign, oras, gh, helm, kubectl, crane, dotnet, golang"
LABEL org.opencontainers.image.version="${RUNNER_VERSION}"
LABEL org.opencontainers.image.vendor="Hellnet"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.title="ARC Runner"

# hadolint ignore=DL3002
USER root

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm

# hadolint ignore=DL3008
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
    podman \
    buildah \
    skopeo \
    fuse-overlayfs \
    slirp4netns \
    uidmap \
    containernetworking-plugins \
    netavark \
    aardvark-dns \
    && apt-get remove --purge -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin 2>/dev/null || true \
    && apt-get autoremove --purge -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /opt/tools/bin

# Rootless podman — subuid/subgid + permissive policy
RUN echo 'runner:100000:65536' > /etc/subuid && \
    echo 'runner:100000:65536' > /etc/subgid && \
    echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /etc/containers/policy.json

FROM base AS yq

ARG YQ_VERSION

RUN curl -fsSLo /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" && \
    chmod +x /usr/local/bin/yq

FROM base AS trivy

ARG TRIVY_VERSION

RUN curl -fsSLO \
    "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" && \
    tar -xzf "trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" -C /usr/local/bin trivy && \
    chmod +x /usr/local/bin/trivy && \
    rm -f "trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"

FROM base AS cosign

ARG COSIGN_VERSION

RUN curl -fsSLO \
    "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64" && \
    install -m 755 cosign-linux-amd64 /usr/local/bin/cosign && \
    rm -f cosign-linux-amd64

FROM base AS gh

ARG GH_VERSION

RUN curl -fsSL \
    "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    -o /tmp/gh.tar.gz && \
    tar -xzf /tmp/gh.tar.gz -C /tmp && \
    install -m 755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh && \
    rm -rf /tmp/gh*

FROM base AS crane

ARG CRANE_VERSION

RUN curl -fsSLO \
    "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" && \
    tar -xzf "go-containerregistry_Linux_x86_64.tar.gz" -C /tmp && \
    install -m 755 /tmp/crane /usr/local/bin/crane && \
    rm -rf /tmp/go-containerregistry* /tmp/crane

FROM base AS syft

ARG SYFT_VERSION

RUN curl -fsSLO \
    "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_amd64.tar.gz" && \
    tar -xzf "syft_${SYFT_VERSION}_linux_amd64.tar.gz" -C /usr/local/bin syft && \
    chmod +x /usr/local/bin/syft && \
    rm -f "syft_${SYFT_VERSION}_linux_amd64.tar.gz"

FROM base AS grype

ARG GRYPE_VERSION

RUN curl -fsSLO \
    "https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/grype_${GRYPE_VERSION}_linux_amd64.tar.gz" && \
    tar -xzf "grype_${GRYPE_VERSION}_linux_amd64.tar.gz" -C /usr/local/bin grype && \
    chmod +x /usr/local/bin/grype && \
    rm -f "grype_${GRYPE_VERSION}_linux_amd64.tar.gz"

FROM base AS oras

ARG ORAS_VERSION

RUN curl -fsSLO \
    "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_amd64.tar.gz" && \
    tar -xzf "oras_${ORAS_VERSION}_linux_amd64.tar.gz" -C /usr/local/bin oras && \
    chmod +x /usr/local/bin/oras && \
    rm -f "oras_${ORAS_VERSION}_linux_amd64.tar.gz"

FROM base AS kubectl

ARG KUBECTL_VERSION

RUN curl -fsSLO \
    "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    install -m 755 kubectl /usr/local/bin/kubectl && \
    rm -f kubectl

FROM base AS helm

ARG HELM_VERSION

RUN curl -fsSL \
    "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    -o /tmp/helm.tar.gz && \
    tar -xzf /tmp/helm.tar.gz -C /tmp && \
    install -m 755 "/tmp/linux-amd64/helm" /usr/local/bin/helm && \
    rm -rf /tmp/helm*

FROM base AS dotnet

ARG DOTNET_CHANNEL

RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    bash /tmp/dotnet-install.sh --channel ${DOTNET_CHANNEL} --install-dir /usr/share/dotnet && \
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet && \
    rm -f /tmp/dotnet-install.sh

FROM base AS golang

ARG GOLANG_VERSION

RUN curl -fsSL \
    "https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz" \
    -o /tmp/go.tar.gz && \
    tar -xzf /tmp/go.tar.gz -C /usr/local && \
    rm -f /tmp/go.tar.gz

FROM base AS final

LABEL org.opencontainers.image.base.name="summerwind/actions-runner:v${RUNNER_VERSION}-ubuntu-24.04"

# Copy tools from build stages
COPY --from=yq     /usr/local/bin/yq       /usr/local/bin/yq
COPY --from=trivy  /usr/local/bin/trivy    /usr/local/bin/trivy
COPY --from=cosign /usr/local/bin/cosign   /usr/local/bin/cosign
COPY --from=gh     /usr/local/bin/gh       /usr/local/bin/gh
COPY --from=crane  /usr/local/bin/crane    /usr/local/bin/crane
COPY --from=syft   /usr/local/bin/syft     /usr/local/bin/syft
COPY --from=grype  /usr/local/bin/grype    /usr/local/bin/grype
COPY --from=oras   /usr/local/bin/oras     /usr/local/bin/oras
COPY --from=kubectl /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=helm   /usr/local/bin/helm     /usr/local/bin/helm
COPY --from=dotnet /usr/share/dotnet       /usr/share/dotnet
COPY --from=golang /usr/local/go           /usr/local/go

# Podman config files (rootless)
COPY containers.conf /home/runner/.config/containers/containers.conf
COPY storage.conf    /home/runner/.config/containers/storage.conf

# Runner user home setup
RUN mkdir -p /home/runner/.gnupg /home/runner/.local/share/containers && \
    chmod 700 /home/runner/.gnupg && \
    chown -R runner:runner /home/runner && \
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet

# Prevent summerwind entrypoint from trying to start dockerd
ENV START_DOCKERD=false

# Runtime directories
ENV RUNNER_WORK_DIRECTORY=/home/runner/_work
ENV RUNNER_TEMP=/home/runner/_temp
ENV RUNNER_TOOL_CACHE=/home/runner/_tool

# Prepend Go and Dotnet to PATH to avoid shadowing system tools
ENV PATH="/usr/local/go/bin:/usr/share/dotnet:/opt/tools/bin:${PATH}"

# .NET CI hygiene
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
ENV NUGET_PACKAGES=/home/runner/.nuget/packages

# Go CI hygiene
ENV GOPATH=/home/runner/go
ENV GOCACHE=/home/runner/.cache/go-build
ENV GOMODCACHE=/home/runner/go/pkg/mod
ENV GOFLAGS=-mod=mod

WORKDIR /home/runner
USER runner
