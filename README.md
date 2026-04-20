# pivpn-revoked-cleanup
Utility script for deep cleanup of revoked PiVPN OpenVPN clients, including Easy-RSA PKI artifacts and CA index (index.txt) entries.

## Download and run

Download the script directly from GitHub:

```bash
wget https://raw.githubusercontent.com/mar-tin-666/pivpn-revoked-cleanup/main/pivpn-revoked-cleanup.sh
```

Make it executable:

```bash
sudo chmod +x pivpn-revoked-cleanup.sh
```

Run it as root (using sudo):

```bash
sudo ./pivpn-revoked-cleanup.sh
```

## What the script does

The script automatically:

- detects the Easy-RSA directory and the target CRL path,
- gets the list of revoked certificates from PiVPN,
- creates a backup of `index.txt`,
- removes revoked client artifacts (`.crt`, `.key`, `.req`, `.ovpn`),
- removes client entries from `clients.txt` and `index.txt`,
- generates a new `crl.pem` and copies it to the OpenVPN directory,
- asks whether to restart the OpenVPN service immediately.

## Important

- The script must be run with root privileges.
- Before restarting OpenVPN, the script warns about possible disconnection of active VPN/SSH sessions.
- Check for newer versions in the repository: https://github.com/mar-tin-666/pivpn-revoked-cleanup
