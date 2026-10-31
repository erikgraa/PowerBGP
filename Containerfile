# PowerBGP in a PowerShell container. Lab use only.
#
#   podman build -f Containerfile -t powerbgp .
#   podman run -it --rm --network host powerbgp
#
# Host networking lets sessions reach lab devices directly. Port 179 needs root in the container (the default).
# TCP-MD5 sessions worked in a rootful Podman container; add --cap-add NET_ADMIN if your runtime restricts it.
FROM mcr.microsoft.com/powershell:lts-ubuntu-22.04

COPY . /usr/local/share/powershell/Modules/PowerBGP
RUN rm -rf /usr/local/share/powershell/Modules/PowerBGP/.git /usr/local/share/powershell/Modules/PowerBGP/Containerfile \
    && pwsh -NoProfile -Command "Import-Module PowerBGP; Get-Module PowerBGP | Select-Object Name, Version"

ENTRYPOINT ["pwsh", "-NoLogo", "-NoExit", "-Command", "Import-Module PowerBGP"]
