#wireguard-install.sh
#!/bin/bash

# Non-interactive WireGuard installer
# Based on: https://github.com/angristan/wireguard-install

RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

function isRoot() {
    if [ "${EUID}" -ne 0 ]; then
        echo "You need to run this script as root"
        exit 1
    fi
}

function checkVirt() {
    function openvzErr() {
        echo "OpenVZ is not supported"
        exit 1
    }
    function lxcErr() {
        echo "LXC is not supported (yet)."
        exit 1
    }
    if command -v virt-what &>/dev/null; then
        if [ "$(virt-what)" == "openvz" ]; then openvzErr; fi
        if [ "$(virt-what)" == "lxc" ]; then lxcErr; fi
    else
        if [ "$(systemd-detect-virt)" == "openvz" ]; then openvzErr; fi
        if [ "$(systemd-detect-virt)" == "lxc" ]; then lxcErr; fi
    fi
}

function checkOS() {
    source /etc/os-release
    OS="${ID}"
    if [[ ${OS} == "debian" || ${OS} == "raspbian" ]]; then
        if [[ ${VERSION_ID} -lt 10 ]]; then
            echo "Debian version not supported (<10)"
            exit 1
        fi
        OS=debian
    elif [[ ${OS} == "ubuntu" ]]; then
        RELEASE_YEAR=$(echo "${VERSION_ID}" | cut -d'.' -f1)
        if [[ ${RELEASE_YEAR} -lt 18 ]]; then
            echo "Ubuntu version not supported (<18.04)"
            exit 1
        fi
    elif [[ ${OS} == "fedora" ]]; then
        if [[ ${VERSION_ID} -lt 32 ]]; then
            echo "Fedora version not supported (<32)"
            exit 1
        fi
    fi
}

function getHomeDirForClient() {
    local CLIENT_NAME=$1
    if [ -e "/home/${CLIENT_NAME}" ]; then
        echo "/home/${CLIENT_NAME}"
    elif [ "${SUDO_USER}" ]; then
        if [ "${SUDO_USER}" == "root" ]; then
            echo "/root"
        else
            echo "/home/${SUDO_USER}"
        fi
    else
        echo "/root"
    fi
}

function installWireGuard() {
    # Auto-detect or set defaults
    SERVER_PUB_IP="${SERVER_PUB_IP:-$(ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)}"
    SERVER_PUB_NIC="${SERVER_PUB_NIC:-$(ip -4 route ls | grep default | awk '{print $5}' | head -1)}"
    SERVER_WG_NIC="${SERVER_WG_NIC:-wg0}"
    SERVER_WG_IPV4="${SERVER_WG_IPV4:-10.66.66.1}"
    SERVER_WG_IPV6="${SERVER_WG_IPV6:-fd42:42:42::1}"
    SERVER_PORT="${SERVER_PORT:-51820}"
    CLIENT_DNS_1="${CLIENT_DNS_1:-1.1.1.1}"
    CLIENT_DNS_2="${CLIENT_DNS_2:-1.0.0.1}"
    ALLOWED_IPS="${ALLOWED_IPS:-0.0.0.0/0,::/0}"

    # Install WireGuard tools
    if [[ ${OS} == 'ubuntu' || ${OS} == 'debian' ]]; then
        apt-get update
        apt-get install -y wireguard iptables resolvconf qrencode
    elif [[ ${OS} == 'fedora' ]]; then
        dnf install -y wireguard-tools iptables qrencode
    fi

    mkdir -p /etc/wireguard
    chmod 600 -R /etc/wireguard

    SERVER_PRIV_KEY=$(wg genkey)
    SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

    # Save server params
    echo "SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_WG_IPV6=${SERVER_WG_IPV6}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}" >/etc/wireguard/params

    # Create server interface
    echo "[Interface]
Address = ${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}" >"/etc/wireguard/${SERVER_WG_NIC}.conf"

    systemctl enable "wg-quick@${SERVER_WG_NIC}"
    systemctl start "wg-quick@${SERVER_WG_NIC}"

    newClient
}

function newClient() {
    # Non-interactive client creation
    CLIENT_NAME="${CLIENT_NAME:-client$(date +%s)}"
    CLIENT_EXISTS=$(grep -c -E "^### Client ${CLIENT_NAME}\$" "/etc/wireguard/${SERVER_WG_NIC}.conf")
    if [[ ${CLIENT_EXISTS} != 0 ]]; then
        CLIENT_NAME="${CLIENT_NAME}_$(date +%s)"
    fi


    for DOT_IP in {2..254}; do
        DOT_EXISTS=$(grep -c "${SERVER_WG_IPV4::-1}${DOT_IP}" "/etc/wireguard/${SERVER_WG_NIC}.conf")
        if [[ ${DOT_EXISTS} == '0' ]]; then break; fi
    done

    CLIENT_WG_IPV4="${SERVER_WG_IPV4::-1}${DOT_IP}"
    CLIENT_WG_IPV6="${SERVER_WG_IPV6::-1}${DOT_IP}"

    CLIENT_PRIV_KEY=$(wg genkey)
    CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
    CLIENT_PRE_SHARED_KEY=$(wg genpsk)
    HOME_DIR=$(getHomeDirForClient "${CLIENT_NAME}")

    echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
Endpoint = ${SERVER_PUB_IP}:${SERVER_PORT}
AllowedIPs = ${ALLOWED_IPS}" >"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

    echo -e "\n### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"

    wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")

    if command -v qrencode &>/dev/null; then
        qrencode -t ansiutf8 -l L <"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
    fi

    echo -e "${GREEN}Client config created at: ${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf${NC}"
}

# --- MAIN ---
isRoot
checkOS
checkVirt

# If WireGuard already installed, just add client; else install server
if [[ -e /etc/wireguard/params ]]; then
    source /etc/wireguard/params
    newClient
else
    installWireGuard
fi
