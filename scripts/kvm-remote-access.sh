#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# KVM Remote Management & Host-to-VM Port Forwarding Helper
# -----------------------------------------------------------------------------
# Helps access and manage KVM virtual machines from another host on the network:
#   1. Shows remote virt-manager, virsh, Cockpit Web UI, and SSH ProxyJump info
#   2. Optionally enables/disables iptables DNAT port forwarding on the KVM host
#      so remote machines can access Forgejo Web UI (:3000) and Git SSH (:222)
#      directly via the KVM host's LAN IP address.
# -----------------------------------------------------------------------------

ACTION="${1:-status}"
shift || true

VM_IP="192.168.122.100"
RUNNER_IP="192.168.122.101"
HTTP_PORT="3000"
GIT_SSH_PORT="222"
HOST_USER="${USER:-ubuntu}"
HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
HOST_IP="${HOST_IP:-$(hostname)}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vm-ip)
            VM_IP="$2"
            shift 2
            ;;
        --runner-ip)
            RUNNER_IP="$2"
            shift 2
            ;;
        --http-port)
            HTTP_PORT="$2"
            shift 2
            ;;
        --ssh-port)
            GIT_SSH_PORT="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

enable_forwarding() {
    echo "--> Enabling IPv4 forwarding and iptables DNAT port forwarding to KVM VM (${VM_IP})..."
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

    # Allow forwarding to virbr0 in FORWARD chain
    sudo iptables -C FORWARD -d "${VM_IP}/32" -p tcp -m multiport --dports "${HTTP_PORT},${GIT_SSH_PORT}" -j ACCEPT 2>/dev/null || \
        sudo iptables -I FORWARD 1 -d "${VM_IP}/32" -p tcp -m multiport --dports "${HTTP_PORT},${GIT_SSH_PORT}" -j ACCEPT

    # Forward Host:3000 -> VM:3000 and Host:222 -> VM:222
    for PORT in "${HTTP_PORT}" "${GIT_SSH_PORT}"; do
        sudo iptables -t nat -C PREROUTING -p tcp -d "${HOST_IP}" --dport "${PORT}" -j DNAT --to-destination "${VM_IP}:${PORT}" 2>/dev/null || \
            sudo iptables -t nat -A PREROUTING -p tcp -d "${HOST_IP}" --dport "${PORT}" -j DNAT --to-destination "${VM_IP}:${PORT}"

        sudo iptables -t nat -C OUTPUT -p tcp -d "${HOST_IP}" --dport "${PORT}" -j DNAT --to-destination "${VM_IP}:${PORT}" 2>/dev/null || \
            sudo iptables -t nat -A OUTPUT -p tcp -d "${HOST_IP}" --dport "${PORT}" -j DNAT --to-destination "${VM_IP}:${PORT}"

        sudo iptables -t nat -C POSTROUTING -p tcp -d "${VM_IP}" --dport "${PORT}" -j MASQUERADE 2>/dev/null || \
            sudo iptables -t nat -A POSTROUTING -p tcp -d "${VM_IP}" --dport "${PORT}" -j MASQUERADE
    done

    echo "✅ Port forwarding enabled:"
    echo "   http://${HOST_IP}:${HTTP_PORT}  -->  http://${VM_IP}:${HTTP_PORT} (Forgejo Web UI)"
    echo "   ssh://git@${HOST_IP}:${GIT_SSH_PORT}  -->  ssh://git@${VM_IP}:${GIT_SSH_PORT} (Forgejo Git SSH)"
}

disable_forwarding() {
    echo "--> Removing iptables DNAT port forwarding rules for ${VM_IP}..."
    while sudo iptables -D FORWARD -d "${VM_IP}/32" -p tcp -m multiport --dports "${HTTP_PORT},${GIT_SSH_PORT}" -j ACCEPT 2>/dev/null; do :; done
    for PORT in "${HTTP_PORT}" "${GIT_SSH_PORT}"; do
        while sudo iptables -t nat -D PREROUTING -p tcp ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL --dport "${PORT}" -j DNAT --to-destination "${VM_IP}:${PORT}" 2>/dev/null; do :; done
        while sudo iptables -t nat -D OUTPUT -p tcp ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL --dport "${PORT}" -j DNAT --to-destination "${VM_IP}:${PORT}" 2>/dev/null; do :; done
        while sudo iptables -t nat -D PREROUTING -p tcp -d "${HOST_IP}" --dport "${PORT}" -j DNAT --to-destination "${VM_IP}:${PORT}" 2>/dev/null; do :; done
        while sudo iptables -t nat -D OUTPUT -p tcp -d "${HOST_IP}" --dport "${PORT}" -j DNAT --to-destination "${VM_IP}:${PORT}" 2>/dev/null; do :; done
        while sudo iptables -t nat -D POSTROUTING -p tcp -d "${VM_IP}" --dport "${PORT}" -j MASQUERADE 2>/dev/null; do :; done
    done
    echo "✅ Port forwarding rules removed."
}

show_status() {
    cat <<EOF
================================================================================
  Remote KVM Management & VM Access Guide (Host IP: ${HOST_IP})
================================================================================

1. Manage KVM VMs Remotely via Virt-Manager (GUI) or Virsh (CLI)
   From another Linux/macOS workstation with SSH access to ${HOST_USER}@${HOST_IP}:

   # Launch Virt-Manager GUI connected to this KVM host:
   virt-manager -c 'qemu+ssh://${HOST_USER}@${HOST_IP}/system?socket=/var/run/libvirt/libvirt-sock'

   # Or use virsh CLI remotely from another host:
   virsh -c 'qemu+ssh://${HOST_USER}@${HOST_IP}/system' list --all
   virsh -c 'qemu+ssh://${HOST_USER}@${HOST_IP}/system' dominfo git-server

2. Manage KVM VMs via Web Browser (Cockpit Machines)
   Open in any browser on another host:
   https://${HOST_IP}:9090
   (Log in with '${HOST_USER}' and your host password -> Click 'Virtual Machines')

3. Direct SSH Access to VMs from Another Host (SSH ProxyJump)
   Add the following to ~/.ssh/config on your remote laptop/workstation:

   Host kvm-host
       HostName ${HOST_IP}
       User ${HOST_USER}

   Host git-server
       HostName ${VM_IP}
       User ubuntu
       ProxyJump kvm-host

   Host git-runner
       HostName ${RUNNER_IP}
       User ubuntu
       ProxyJump kvm-host

   Host git.vm
       HostName ${VM_IP}
       Port ${GIT_SSH_PORT}
       User git
       ProxyJump kvm-host

4. Direct LAN Routing or Host Port Forwarding to VMs
   Option A - Enable Host Port Forwarding (:3000 & :222 on ${HOST_IP} -> ${VM_IP}):
     make kvm-port-forward ACTION=enable

   Option B - Add a static route on your remote client (on the same LAN):
     sudo ip route add 192.168.122.0/24 via ${HOST_IP}
================================================================================
EOF
}

case "${ACTION}" in
    enable)
        enable_forwarding
        ;;
    disable)
        disable_forwarding
        ;;
    status|info|*)
        show_status
        ;;
esac
