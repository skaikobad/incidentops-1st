#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$PWD}"
NODE_MAJOR="${NODE_MAJOR:-20}"
MONGODB_MAJOR="${MONGODB_MAJOR:-8.0}"

# auto    -> native MongoDB on RHEL 8/9, Podman container on RHEL 10
# native  -> force a native install even on RHEL 10 (unsupported/experimental)
# container -> always use the Podman container, even on RHEL 8/9
MONGO_INSTALL_MODE="${MONGO_INSTALL_MODE:-auto}"

MONGO_CONTAINER_NAME="${MONGO_CONTAINER_NAME:-mongodb}"
MONGO_DATA_VOLUME="${MONGO_DATA_VOLUME:-mongo_data}"
MONGO_IMAGE="${MONGO_IMAGE:-docker.io/library/mongo:${MONGODB_MAJOR}}"

if [[ "${EUID}" -eq 0 ]]; then
  echo "Please run this script as a regular sudo-capable user (e.g. ec2-user), not as root. It will ask for sudo when needed."
  exit 1
fi

if ! command -v dnf >/dev/null 2>&1; then
  echo "This installer is designed for RHEL/Rocky/AlmaLinux/CentOS Stream servers using dnf."
  exit 1
fi

# RHEL 10's stricter RPM signature backend (rpm-sequoia) rejects some vendor GPG keys
# (NodeSource, Microsoft, Sublime, etc.) because their self-signatures use SHA-1, which
# fails with "Policy rejects ...: No binding signature" under the DEFAULT crypto policy.
# This imports a key, falling back to a temporarily-relaxed LEGACY policy if needed,
# then restores the original policy. The key only needs the relaxed policy at import
# time; once it's trusted, normal installs succeed under DEFAULT again.
import_gpg_key() {
  local key="$1"
  local log="/tmp/rpm_import_$$.log"

  if sudo rpm --import "$key" 2>"$log"; then
    rm -f "$log"
    return 0
  fi

  if grep -q "No binding signature" "$log"; then
    echo "GPG key '$key' uses an older self-signature RHEL 10's default crypto policy rejects."
    echo "Temporarily switching to the LEGACY crypto policy to import it, then switching back..."
    local original_policy
    original_policy="$(update-crypto-policies --show 2>/dev/null || echo DEFAULT)"

    sudo update-crypto-policies --set LEGACY
    local rc=0
    sudo rpm --import "$key" || rc=$?
    sudo update-crypto-policies --set "$original_policy"

    rm -f "$log"
    return "$rc"
  fi

  cat "$log"
  rm -f "$log"
  return 1
}

source /etc/os-release
DISTRO_ID="${ID:-}"
DISTRO_VERSION="${VERSION_ID:-}"
RHEL_MAJOR="${DISTRO_VERSION%%.*}"

echo "Detected: ${PRETTY_NAME:-$DISTRO_ID $DISTRO_VERSION}"

case "$DISTRO_ID" in
  rhel|rocky|almalinux|centos) ;;
  *)
    echo ""
    echo "Unsupported distribution: ${DISTRO_ID:-unknown}"
    echo "This installer targets RHEL 8, 9, or 10 (and close derivatives: Rocky Linux, AlmaLinux, CentOS Stream)."
    exit 1
    ;;
esac

if [[ "$RHEL_MAJOR" != "8" && "$RHEL_MAJOR" != "9" && "$RHEL_MAJOR" != "10" ]]; then
  echo ""
  echo "Unsupported major version for this project: ${DISTRO_VERSION:-unknown}"
  echo "Please use one of the following:"
  echo "  - RHEL 10"
  echo "  - RHEL 9"
  echo "  - RHEL 8"
  echo ""
  echo "Recommended for students: AWS EC2 'Red Hat Enterprise Linux 10' AMI"
  exit 1
fi

echo "==> Cleaning old/broken MongoDB repositories"
sudo rm -f /etc/yum.repos.d/*mongo*.repo

echo "==> Updating dnf packages"
sudo dnf clean all
sudo dnf makecache
sudo dnf install -y ca-certificates curl gnupg2

echo "==> Installing development toolchain (needed to build native npm modules)"
sudo dnf groupinstall -y "Development Tools" || sudo dnf install -y gcc gcc-c++ make

echo "==> Installing Node.js ${NODE_MAJOR}.x from NodeSource"
# NodeSource now ships a single distro-agnostic ("nodistro") RPM repo instead of
# per-RHEL-version repos, so this works the same way on RHEL 8, 9, and 10.
NODE_RPM_URL="https://rpm.nodesource.com/pub_${NODE_MAJOR}.x/nodistro/repo/nodesource-release-nodistro-1.noarch.rpm"
sudo dnf install -y "$NODE_RPM_URL"

# Import the repo's signing key ourselves (with the LEGACY-policy fallback above) so
# the later 'dnf install nodejs' doesn't fail mid-transaction on the GPG check.
NODE_GPG_KEY="/etc/pki/rpm-gpg/NODESOURCE-NSOLID-GPG-SIGNING-KEY-EL"
if [[ -f "$NODE_GPG_KEY" ]]; then
  import_gpg_key "$NODE_GPG_KEY"
fi

sudo dnf install -y nodejs

echo "Node version: $(node -v)"
echo "npm version: $(npm -v)"

echo "==> Setting up MongoDB Community Server ${MONGODB_MAJOR}"

# Decide native vs. container based on MONGO_INSTALL_MODE and the detected RHEL version.
MONGO_RUNTIME="native"
if [[ "$MONGO_INSTALL_MODE" == "container" ]]; then
  MONGO_RUNTIME="container"
elif [[ "$MONGO_INSTALL_MODE" == "auto" && "$RHEL_MAJOR" == "10" ]]; then
  MONGO_RUNTIME="container"
fi

install_mongo_native() {
  local repo_major="$1"
  echo "==> Installing MongoDB natively (using the RHEL ${repo_major} package repo)"

  import_gpg_key "https://pgp.mongodb.com/server-${MONGODB_MAJOR}.asc"

  sudo tee "/etc/yum.repos.d/mongodb-org-${MONGODB_MAJOR}.repo" >/dev/null <<EOF
[mongodb-org-${MONGODB_MAJOR}]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/${repo_major}/mongodb-org/${MONGODB_MAJOR}/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-${MONGODB_MAJOR}.asc
EOF

  sudo dnf makecache
  sudo dnf install -y mongodb-org

  sudo mkdir -p /var/lib/mongo /var/log/mongodb
  sudo chown -R mongod:mongod /var/lib/mongo /var/log/mongodb

  sudo systemctl daemon-reload
  sudo systemctl enable --now mongod
}

install_mongo_container() {
  echo "==> MongoDB has no official RHEL 10 packages yet, so this runs it in a Podman container instead."
  echo "    (Native MongoDB RPMs built for RHEL 9 are known to install on RHEL 10 but fail to start"
  echo "    mongod due to OpenSSL/library mismatches, so a container is the reliable path for now.)"

  if ! command -v podman >/dev/null 2>&1; then
    sudo dnf install -y podman
  fi

  sudo podman volume inspect "$MONGO_DATA_VOLUME" >/dev/null 2>&1 || sudo podman volume create "$MONGO_DATA_VOLUME"
  sudo podman rm -f "$MONGO_CONTAINER_NAME" >/dev/null 2>&1 || true

  sudo podman pull "$MONGO_IMAGE"

  # Bind only to localhost; the app talks to it over 127.0.0.1, same as it would with a native install.
  sudo podman create \
    --name "$MONGO_CONTAINER_NAME" \
    -v "${MONGO_DATA_VOLUME}:/data/db" \
    -p 127.0.0.1:27017:27017 \
    "$MONGO_IMAGE"

  # Generate a real systemd unit so the container starts on boot and behaves like a normal service.
  (cd /etc/systemd/system && sudo podman generate systemd --new --name "$MONGO_CONTAINER_NAME" --files --restart-policy=always)

  sudo systemctl daemon-reload
  sudo systemctl enable --now "container-${MONGO_CONTAINER_NAME}.service"
}

if [[ "$MONGO_RUNTIME" == "native" ]]; then
  if [[ "$RHEL_MAJOR" == "10" ]]; then
    echo ""
    echo "WARNING: forcing a native MongoDB install on RHEL 10 (MONGO_INSTALL_MODE=native)."
    echo "MongoDB has no official RHEL 10 build yet; this uses the RHEL 9 packages and may fail"
    echo "to start mongod due to OpenSSL/library mismatches. Re-run with MONGO_INSTALL_MODE=container"
    echo "(the default) if this does not work."
    echo "Attempting a legacy crypto policy as a known workaround for libcrypto errors..."
    sudo update-crypto-policies --set LEGACY || true
    install_mongo_native "9"
  else
    install_mongo_native "$RHEL_MAJOR"
  fi
else
  install_mongo_container
fi

sleep 10

if [[ "$MONGO_RUNTIME" == "native" ]]; then
  echo "MongoDB service: $(systemctl is-active mongod 2>/dev/null || echo unknown)"
else
  echo "MongoDB service: $(systemctl is-active "container-${MONGO_CONTAINER_NAME}.service" 2>/dev/null || echo unknown)"
fi

echo "==> Opening firewalld ports for the app"
# RHEL ships firewalld enabled by default (unlike Ubuntu's ufw, which is off by default),
# so without this the app is unreachable even with a correct AWS security group.
if systemctl is-active --quiet firewalld; then
  sudo firewall-cmd --permanent --add-port=5173/tcp
  sudo firewall-cmd --permanent --add-port=5001/tcp
  sudo firewall-cmd --reload
else
  echo "firewalld is not active; skipping (make sure your AWS security group allows 5173/5001)."
fi

echo "==> Creating environment files if missing"
cd "$APP_DIR"

if [[ ! -f backend/.env ]]; then
  cp backend/.env.example backend/.env
fi

if [[ ! -f frontend/.env ]]; then
  cp frontend/.env.example frontend/.env
fi

echo "==> Installing project dependencies"
npm install
npm run install:all

echo "==> Seeding database"
npm run seed

echo ""
echo "Installation complete."
echo "Node: $(node -v)"
echo "npm: $(npm -v)"
if [[ "$MONGO_RUNTIME" == "native" ]]; then
  echo "MongoDB service: $(systemctl is-active mongod 2>/dev/null || echo unknown)"
else
  echo "MongoDB service: $(systemctl is-active "container-${MONGO_CONTAINER_NAME}.service" 2>/dev/null || echo unknown) (Podman container)"
fi
echo ""
echo "Run the app with:"
echo "npm run dev"
echo ""
echo "Frontend:"
echo "http://YOUR_VM_PUBLIC_IP:5173"
echo ""
echo "Backend health:"
echo "http://YOUR_VM_PUBLIC_IP:5001/api/health"
echo ""
echo "Login:"
echo "admin@auto-reliability.com / hello123"
