FROM mcr.microsoft.com/powershell:lts-ubuntu-18.04

RUN pwsh -command "Install-Module -Name Az -AllowClobber -Force"

COPY endjin.deployment /usr/local/share/powershell/Modules/endjin.deployment
