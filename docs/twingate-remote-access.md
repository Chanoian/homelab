# Twingate Remote Access

Use Twingate for private remote access to the lab. Do not expose OpenShift ports on the
home router.

## Connector Placement

Run the Connector inside the home network. The Raspberry Pi is the preferred target
because it is already always on and runs CoreDNS for `main.araclab.xyz`.

The Connector must be able to resolve and reach:

- `api.main.araclab.xyz`
- `*.apps.main.araclab.xyz`
- `192.168.2.50`, if SSH access is enabled

## Resources

| Resource | Address | Ports |
|---|---|---|
| API Main | `api.main.araclab.xyz` | TCP 6443 |
| Wild Apps | `*.apps.main.araclab.xyz` | TCP 443 |
| SSH Node | `192.168.2.50` | TCP 22 |

Add TCP 80 to `Wild Apps` only if a route or redirect explicitly needs plain HTTP.

## Tests

From the Raspberry Pi:

```bash
dig @127.0.0.1 api.main.araclab.xyz
dig @127.0.0.1 console-openshift-console.apps.main.araclab.xyz
```

From a remote client with Twingate connected:

```bash
oc --kubeconfig kubeconfig-noingress get nodes
```

Open:

```text
https://console-openshift-console.apps.main.araclab.xyz
```
