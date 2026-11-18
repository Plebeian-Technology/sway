---
lat:
  mode: how-to
---
# Troubleshoot deploys

How to resolve common deployment failures.

## No route to host (EHOSTUNREACH)

When the deploy fails because Kamal cannot reach the production machine, it is often a broken local routing table rather than a down machine.

1. Verify the machine is actually up by connecting with standard SSH. If standard SSH connects but Kamal does not, the macOS kernel's routing table or firewall extension is wedged.
2. If you reach the machine over Tailscale, restart it with `sudo tailscale down && sudo tailscale up` and leave it running. Otherwise, fully quit any VPN client.
3. Toggle Wi-Fi off and on.
4. If the error persists, restart the Mac to flush the ephemeral routing table and reload network extensions.

## Tailscale is not active

[[scripts/deploy.sh]] warns at the start of a run when `deploy/config/sway.env` uses Tailscale and Tailscale is missing or stopped here. It counts as used when `SWAY_TAILSCALE_IP` is set or `SWAY_HOST` is a `100.x` address.

1. Open the Tailscale app, or run `tailscale up`.
2. Run `tailscale status` and confirm it lists the serving machine and the standby machine.
3. Run `ssh <deploy user>@<SWAY_HOST> hostname` and confirm it answers.
4. Run [[scripts/deploy.sh]] again.

## Registry login times out

When `docker login` to the image store fails with `Client.Timeout exceeded while awaiting headers` while the machine itself answers, the name lookup is usually what ran out of time.

A name ending in `.local` is sent to multicast DNS. A host-table line answers the IPv4 question, but nothing answers the IPv6 one, so the lookup waits until it times out.

1. Time the lookup inside Docker: `docker run --rm alpine sh -c 'apk add -q bind-tools; time dig +short <registry name> AAAA'`.
2. If it takes seconds, add an IPv6 line for the name to `/etc/hosts` holding the IPv4-mapped form of its address, for example `::ffff:100.64.0.10 <registry name>`.
3. Repeat step 1 and confirm the answer is instant.
4. Run `scripts/deploy.sh --preflight-only` and confirm the image store line reads `ok`.

