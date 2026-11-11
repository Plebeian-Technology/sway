---
lat:
  mode: how-to
---
# Troubleshoot deploys

How to resolve common deployment failures.

## No route to host (EHOSTUNREACH)

When the deploy fails because Kamal cannot reach the production machine on its local IP, it is often a broken local routing table rather than a down machine.

1. Verify the machine is actually up by connecting with standard SSH. If standard SSH connects but Kamal does not, the macOS kernel's routing table or firewall extension is wedged.
2. Fully quit any VPN clients (like Tailscale) and toggle Wi-Fi off and on.
3. For Tailscale specifically, run `sudo tailscale down && sudo tailscale up`.
4. If the error persists, restart the Mac to flush the ephemeral routing table and reload network extensions.
