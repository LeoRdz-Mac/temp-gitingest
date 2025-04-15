#!/usr/bin/env bash
set -euo pipefail

# ──── Styled Output ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ──── Validate Environment ──────────────────────────────────────────
check_wsl() {
  if ! grep -qi microsoft /proc/version; then
    warning "This script is optimized for WSL2 environments"
  fi
}

check_root() {
  if [[ $EUID -eq 0 ]]; then
    error "This script should NOT be run as root. Run as your normal user."
  fi
}

# ──── Permission Fixes ──────────────────────────────────────────────
fix_onboarding_permissions() {
  local ONBOARDING_DIR="/opt/onboarding"
  
  info "Fixing permissions for ${ONBOARDING_DIR}"
  
  # Root-owned files (require sudo)
  sudo find "${ONBOARDING_DIR}" -type d -exec chmod 755 {} \;
  sudo find "${ONBOARDING_DIR}" -type f -exec chmod 644 {} \;
  
  # Make scripts executable
  sudo find "${ONBOARDING_DIR}/scripts" -type f -name "*.sh" -exec chmod +x {} \;
  sudo find "${ONBOARDING_DIR}/lib" -type f -name "*.sh" -exec chmod +x {} \;
  
  # Log files should be writable
  sudo chmod 775 "${ONBOARDING_DIR}/logs" || warning "Couldn't modify logs directory"
  sudo touch "${ONBOARDING_DIR}/logs/permissions-fixed-$(date +%Y%m%d).log"
  
  # Special files
  [[ -f "${ONBOARDING_DIR}/.bootstrap-root-done" ]] && sudo chmod 644 "${ONBOARDING_DIR}/.bootstrap-root-done"
  [[ -f "${ONBOARDING_DIR}/.bootstrap-user-done" ]] && sudo chmod 644 "${ONBOARDING_DIR}/.bootstrap-user-done"
  
  # Ensure proper ownership
  if id -u "${USER}" >/dev/null 2>&1; then
    sudo chown -R root:root "${ONBOARDING_DIR}"
    sudo chown -R "${USER}:${USER}" "${ONBOARDING_DIR}/logs"
  else
    warning "Current user not found, skipping ownership changes"
  fi
}

fix_ansible_project_permissions() {
  local PROJECT_DIR="${1:-$(pwd)}"
  
  info "Fixing permissions for Ansible project at ${PROJECT_DIR}"
  
  # Directory structure
  find "${PROJECT_DIR}" -type d -exec chmod 755 {} \;
  
  # Files
  find "${PROJECT_DIR}" -type f -exec chmod 644 {} \;
  
  # Executables
  chmod +x "${PROJECT_DIR}/fix-permissions.sh"
  [[ -f "${PROJECT_DIR}/playbook.yml" ]] && chmod 644 "${PROJECT_DIR}/playbook.yml"
  
  # Sensitive files
  for file in hosts inventory ansible.cfg; do
    if [[ -f "${PROJECT_DIR}/${file}" ]]; then
      chmod 600 "${PROJECT_DIR}/${file}"
      info "Secured permissions for ${file}"
    fi
  done
}

fix_user_home_permissions() {
  info "Securing home directory permissions"
  
  # Strict permissions for SSH
  chmod 700 ~/.ssh || warning "No .ssh directory found"
  [[ -d ~/.ssh ]] && find ~/.ssh -type f -exec chmod 600 {} \;
  
  # GPG directory
  chmod 700 ~/.gnupg || warning "No .gnupg directory found"
  
  # Chezmoi and dotfiles
  [[ -d ~/.local/share/chezmoi ]] && chmod 750 ~/.local/share/chezmoi
}

# ──── Main Execution ───────────────────────────────────────────────
main() {
  check_wsl
  check_root
  
  # Fix permissions in order of importance
  fix_onboarding_permissions
  fix_ansible_project_permissions "$(dirname "$0")"
  fix_user_home_permissions
  
  info "Permission fixes complete!"
  echo -e "Recommended next steps:"
  echo -e "1. Verify with: ${YELLOW}ls -la /opt/onboarding${NC}"
  echo -e "2. Check logs: ${YELLOW}ls -la /opt/onboarding/logs${NC}"
  echo -e "3. Validate SSH: ${YELLOW}ls -la ~/.ssh${NC}"
}

# Execute
main "$@"
