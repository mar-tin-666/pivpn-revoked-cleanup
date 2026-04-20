#!/bin/bash

# ----------------------------------------------
# Author: mar-tin-666
# Source: https://github.com/mar-tin-666/pivpn-revoked-cleanup
# Updates: Check the repository above for newer versions.
# ----------------------------------------------

set -u

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERROR] $*" >&2; }

require_root() {
  if [ "$EUID" -ne 0 ]; then
    err "Run as root"
    exit 1
  fi
}

detect_easyrsa_dir() {
  if [ -d "/etc/openvpn/easy-rsa" ]; then
    EASYRSA_DIR="/etc/openvpn/easy-rsa"
  elif [ -d "/etc/openvpn/server/easy-rsa" ]; then
    EASYRSA_DIR="/etc/openvpn/server/easy-rsa"
  else
    err "Easy-RSA not found"
    exit 1
  fi
}

detect_crl_target() {
  if [ -d "/etc/openvpn/server" ]; then
    CRL_TARGET="/etc/openvpn/server/crl.pem"
  else
    CRL_TARGET="/etc/openvpn/crl.pem"
  fi
}

get_revoked_profiles() {
  pivpn -l 2>/dev/null | awk '
    /Certificate Status List/ { in_table=1; next }
    in_table && $1 == "Status" { next }
    in_table && $1 == "Revoked" { print $2 }
  ' | sed '/^$/d' | sort -u
}

backup_index() {
  INDEX_FILE="$EASYRSA_DIR/pki/index.txt"

  if [ ! -f "$INDEX_FILE" ]; then
    err "index.txt not found: $INDEX_FILE"
    exit 1
  fi

  BACKUP_FILE="${INDEX_FILE}.bak.$(date +%s)"
  cp "$INDEX_FILE" "$BACKUP_FILE"
  log "Backup created: $BACKUP_FILE"
}

remove_from_index() {
  local profile="$1"
  local index_file="$EASYRSA_DIR/pki/index.txt"

  log "Removing $profile from index.txt"
  sed -i "\|/CN=${profile}\$|d" "$index_file"
}

remove_client_files() {
  local profile="$1"

  log "Removing client files for profile: $profile"
  find /home -type f -name "${profile}.ovpn" -delete 2>/dev/null
  find /root -type f -name "${profile}.ovpn" -delete 2>/dev/null
}

remove_easyrsa_artifacts() {
  local profile="$1"

  log "Removing Easy-RSA artifacts for profile: $profile"
  rm -f "$EASYRSA_DIR/pki/issued/${profile}.crt"
  rm -f "$EASYRSA_DIR/pki/private/${profile}.key"
  rm -f "$EASYRSA_DIR/pki/reqs/${profile}.req"
}

clean_clients_txt() {
  local profile="$1"

  if [ -f "/etc/pivpn/clients.txt" ]; then
    log "Removing ${profile} from /etc/pivpn/clients.txt"
    sed -i "\|^${profile}|d" /etc/pivpn/clients.txt
  fi
}

regenerate_crl() {
  log "Regenerating CRL"

  cd "$EASYRSA_DIR" || exit 1

  ./easyrsa gen-crl
  if [ $? -ne 0 ]; then
    err "easyrsa gen-crl failed"
    exit 1
  fi

  if [ ! -f "$EASYRSA_DIR/pki/crl.pem" ]; then
    err "Generated CRL not found"
    exit 1
  fi

  cp "$EASYRSA_DIR/pki/crl.pem" "$CRL_TARGET"
  chmod 644 "$CRL_TARGET"
}

get_restart_command() {
  if systemctl list-unit-files 2>/dev/null | grep -q '^openvpn-server@server\.service'; then
    echo "systemctl restart openvpn-server@server.service"
    return
  fi

  if systemctl list-unit-files 2>/dev/null | grep -q '^openvpn@server\.service'; then
    echo "systemctl restart openvpn@server.service"
    return
  fi

  if systemctl list-unit-files 2>/dev/null | grep -q '^openvpn@\.service'; then
    echo "systemctl restart openvpn@server"
    return
  fi

  echo "systemctl restart openvpn"
}

confirm_and_restart_openvpn() {
  local restart_cmd
  local answer

  restart_cmd="$(get_restart_command)"

  echo
  warn "Required: restart of the OpenVPN server service."
  warn "If you do it now, all currently active VPN connections will be restarted."
  warn "Your current SSH session may also be disconnected."
  echo

  printf "Do you want to restart OpenVPN now? [Y/N]: "
  read answer

  case "$answer" in
    Y|y)
      log "Restarting OpenVPN using: $restart_cmd"
      eval "$restart_cmd"
      ;;
    N|n)
      warn "OpenVPN was NOT restarted."
      warn "Run this command manually later:"
      echo "  sudo $restart_cmd"
      ;;
    *)
      warn "Invalid answer. OpenVPN was NOT restarted."
      warn "Run this command manually later:"
      echo "  sudo $restart_cmd"
      ;;
  esac
}

main() {
  log "Author: Marcin Bischoff (mar-tin-666)"
  log "Source: https://github.com/mar-tin-666/pivpn-revoked-cleanup"
  log "Check the repository for newer versions of this script"
  log "Starting PiVPN revoked profiles cleanup"

  require_root
  detect_easyrsa_dir
  detect_crl_target

  log "Using Easy-RSA: $EASYRSA_DIR"
  log "Using CRL target: $CRL_TARGET"

  mapfile -t revoked < <(get_revoked_profiles)

  if [ "${#revoked[@]}" -eq 0 ]; then
    log "No revoked profiles found"
    exit 0
  fi

  log "Revoked profiles found: ${revoked[*]}"

  backup_index

  for profile in "${revoked[@]}"; do
    remove_client_files "$profile"
    remove_easyrsa_artifacts "$profile"
    clean_clients_txt "$profile"
    remove_from_index "$profile"
  done

  regenerate_crl
  confirm_and_restart_openvpn

  log "DONE - cleanup finished"
}

main
