#!/usr/bin/env bash
set -euo pipefail

readonly REPO="kamilpopowicz/PasswordMonitor"
readonly ASSET_NAME="PasswordMonitor.app.zip"
readonly APP_NAME="PasswordMonitor.app"
readonly INSTALL_DIR="/Applications"
readonly DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"

tmp_dir="$(/usr/bin/mktemp -d)"
cleanup() {
  /bin/rm -rf "${tmp_dir}"
}
trap cleanup EXIT

zip_path="${tmp_dir}/${ASSET_NAME}"
extract_dir="${tmp_dir}/extract"
app_path="${extract_dir}/${APP_NAME}"
target_path="${INSTALL_DIR}/${APP_NAME}"

/bin/mkdir -p "${extract_dir}"

echo "Downloading ${ASSET_NAME}..."
/usr/bin/curl -fL --retry 3 --connect-timeout 15 -o "${zip_path}" "${DOWNLOAD_URL}"

echo "Extracting ${APP_NAME}..."
/usr/bin/ditto -x -k "${zip_path}" "${extract_dir}"

if [[ ! -d "${app_path}" ]]; then
  echo "Error: ${APP_NAME} was not found in the release archive." >&2
  exit 1
fi

echo "Installing ${APP_NAME} to ${INSTALL_DIR}..."
if [[ -w "${INSTALL_DIR}" ]]; then
  /usr/bin/ditto "${app_path}" "${target_path}"
else
  /usr/bin/sudo /usr/bin/ditto "${app_path}" "${target_path}"
fi

echo "Installed ${target_path}"

lsregister_path="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
if [[ -x "${lsregister_path}" ]]; then
  "${lsregister_path}" -f -R -trusted "${target_path}" >/dev/null 2>&1 || true
fi

echo "Opening ${APP_NAME}..."
if ! /usr/bin/open "${target_path}"; then
  echo "Installed, but macOS did not open ${APP_NAME} automatically." >&2
  echo "Open it manually with right-click → Open if Gatekeeper asks for confirmation." >&2
fi
