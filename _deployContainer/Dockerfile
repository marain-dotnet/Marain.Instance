FROM mcr.microsoft.com/powershell:lts-ubuntu-18.04

# Install Az cmdlets
RUN pwsh -command "Install-Module -Name Az -AllowClobber -Force"

# Install azure-cli
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        gpg \
    && curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor | \
        tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null \
    && echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ bionic main" | \
        tee /etc/apt/sources.list.d/azure-cli.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        azure-cli \
    && rm -rf /var/lib/apt/lists/*

COPY endjin.deployment /usr/local/share/powershell/Modules/endjin.deployment
