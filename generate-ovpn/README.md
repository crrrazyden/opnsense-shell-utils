# opnsense-ovpn-generator

A shell script for OPNsense that generates `.ovpn` client config files directly from `/conf/config.xml`.

Supports **multiple CA certificates** in a single config — useful for smooth CA migration without disconnecting existing clients.

## Requirements

- OPNsense (FreeBSD-based)
- `xmllint` (usually pre-installed)
- `base64` (usually pre-installed)

## Usage

```sh
# Generate config for a user
./generate-ovpn.sh "John Doe" "vpn1_ca" 

# Generate config with additional CA (for migration)
./generate-ovpn.sh "John Doe" "vpn1_ca" "vpn1_ca_2036"

# List all available CAs from config.xml
./generate-ovpn.sh showca
```

Output file: `John Doe.ovpn`

## CA Migration Workflow

When your CA certificate is about to expire, you can add a new CA alongside the old one so clients continue to work during the transition:

1. Create a new CA in OPNsense with a **different CN** (e.g. `vpn1_ca_2036`)
2. Generate new `.ovpn` files with both CAs: `./generate-ovpn.sh "username" "vpn1_ca" "vpn1_ca_2036"`
3. Distribute updated configs to clients — they will trust both CAs
4. Issue a new server certificate signed by the new CA
5. Gradually reissue client certificates under the new CA
6. After the old CA expires — remove it from the bundle

## Configuration

Edit the variables at the top of the script:

```sh
OPENVPN_HOST="your.vpn.host"
OPENVPN_PORT=1194
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid CA name |
| 2 | Invalid user name |
| 3 | CA not found in config.xml |
| 4 | User certificate not found in config.xml |

## Author

Denis Ivanov  
License: MIT
