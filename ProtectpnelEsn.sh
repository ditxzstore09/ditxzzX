#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║ Shaasleep Shield – Pterodactyl Hardening Kit        (c) 2025 Shaasleep ║
# ╚══════════════════════════════════════════════════════════════════════╝
#  :: Built for Pterodactyl 1.11.x – run as root – no warranty ::

set -euo pipefail
shopt -s expand_aliases
alias log='echo "[$(date "+%T")] ▶"'

BOLD='\e[1m'
RED='\e[31m'
GRN='\e[32m'
YLW='\e[33m'
BLU='\e[34m'
MGT='\e[35m'
CYN='\e[36m'
RST='\e[0m'

banner(){
clear
cat <<'EOF'
╔═══════════════════════════════════════════════════════════════════════╗
║    ____  _   _ ____    _____ _   _ _    _       _____ _    _ _____  ║
║   / ___|| | | / ___|  |_   _| | | | |  | |     |  ___/ \  | |_   _| ║
║   \___ \| | | \___ \    | | | | | | |  | |_____| |_ / _ \ | | | |   ║
║    ___) | |_| |___) |   | | | |_| | |__| |_____|  _/ ___ \| | | |   ║
║   |____/ \___/|____/    |_|  \___/ \____/      |_|/_/   \_\_| |_|   ║
║                                                                       ║
║              Pterodactyl Shield – Sleep tight, host tight.            ║
╚═══════════════════════════════════════════════════════════════════════╝
EOF
}

spinner(){
  local pid=$1; local delay=0.15; local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
  while kill -0 "$pid" 2>/dev/null; do
    for i in $(seq 0 7); do
      printf "${MGT}${spin:$i:1}${RST} "
      sleep $delay
      printf "\b\b"
    done
  done
}

check_root(){
  [[ $EUID -eq 0 ]] || { log "${RED}❌  Run as root homie.${RST}"; exit 1; }
}

check_panel(){
  [[ -d "/var/www/pterodactyl" ]] || { log "${RED}❌  Panel path not found.${RST}"; exit 1; }
}

get_admin(){
  read -rp "$(log "${CYN}🔑 Masukkan ID Admin Utama : ${RST}")" ADMIN_ID
  [[ "$ADMIN_ID" =~ ^[0-9]+$ ]] || { log "${RED}❌  Harus angka!${RST}"; exit 1; }
  log "${GRN}✅  Admin utama → ID ${MGT}${ADMIN_ID}${RST}"
}

persist_env(){
  local env="/var/www/pterodactyl/.env"
  grep -q "^SHIELD_ADMIN_ID=" "$env" \
    && sed -i "s/^SHIELD_ADMIN_ID=.*/SHIELD_ADMIN_ID=$ADMIN_ID/" "$env" \
    || echo "SHIELD_ADMIN_ID=$ADMIN_ID" >> "$env"
}

patch_server_controller(){
  local f="/var/www/pterodactyl/app/Http/Controllers/Api/Client/Server/ServerController.php"
  grep -q "ShaasleepShield" "$f" && { log "${YLW}⚡  ServerController sudah dipatch${RST}"; return; }
  sed -i '/public function index(/a\
        /* ShaasleepShield */\
        $user = auth()->user();\
        if ($user->id != '"$ADMIN_ID"' && (int)$server->owner_id !== (int)$user->id) {\
            abort(403, "🧊 ShaasleepShield: Akses ditolak. Server ini bukan milikmu.");\
        }' "$f"
  log "${GRN}✅  ServerController dipatch${RST}"
}

patch_file_controller(){
  local f="/var/www/pterodactyl/app/Http/Controllers/Api/Client/Server/FileController.php"
  grep -q "ShaasleepShield" "$f" && { log "${YLW}⚡  FileController sudah dipatch${RST}"; return; }
  sed -i '/public function index(/a\
        /* ShaasleepShield */\
        $user = auth()->user();\
        if ($user->id != '"$ADMIN_ID"' && (int)$server->owner_id !== (int)$user->id) {\
            abort(403, "🧊 ShaasleepShield: Akses ditolak.");\
        }' "$f"
  log "${GRN}✅  FileController dipatch${RST}"
}

patch_user_controller(){
  local f="/var/www/pterodactyl/app/Http/Controllers/Admin/UserController.php"
  log "${CYN}🧱  Menulis UserController${RST}"
  cat <<'PHP' > "$f"
<?php
namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\Http\RedirectResponse;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Http\Requests\Admin\UserFormRequest;
use Pterodactyl\Services\Users\UserUpdateService;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Models\User;
use Illuminate\Support\Facades\Auth;

class UserController extends Controller
{
    public function __construct(private UserUpdateService $updateService) {}

    public function update(UserFormRequest $request, User $user): RedirectResponse
    {
        if (Auth::user()->id != env('SHIELD_ADMIN_ID')) {
            throw new DisplayException('🧊 ShaasleepShield: Lu siapa dongo minimal mikir kidz.');
        }
        $this->updateService->handle($user, $request->normalize());
        return redirect()->route('admin.users.view', $user->id)->with('success', 'User updated.');
    }
}
PHP
  log "${GRN}✅  UserController diproteksi${RST}"
}

patch_location_controller(){
  local f="/var/www/pterodactyl/app/Http/Controllers/Admin/LocationController.php"
  log "${CYN}🧱  Menulis LocationController${RST}"
  cat <<'PHP' > "$f"
<?php
namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Pterodactyl\Models\Location;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Http\Requests\Admin\LocationFormRequest;
use Pterodactyl\Services\Locations\{LocationCreationService,LocationUpdateService,LocationDeletionService};
use Illuminate\Support\Facades\Auth;

class LocationController extends Controller
{
    public function __construct(
        private LocationCreationService $creation,
        private LocationUpdateService $update,
        private LocationDeletionService $delete
    ) {}

    private function shield(): void
    {
        if (Auth::user()->id != env('SHIELD_ADMIN_ID')) {
            abort(403, '🧊 ShaasleepShield: Dont not your Access.');
        }
    }

    public function index(): View
    {
        $this->shield();
        return view('admin.locations.index', ['locations' => Location::with('nodes')->get()]);
    }

    public function create(LocationFormRequest $r): RedirectResponse
    {
        $this->shield();
        $loc = $this->creation->handle($r->normalize());
        return redirect()->route('admin.locations.view', $loc->id)->with('success', 'Location created.');
    }

    public function update(LocationFormRequest $r, Location $l): RedirectResponse
    {
        $this->shield();
        $this->update->handle($l->id, $r->normalize());
        return redirect()->route('admin.locations.view', $l->id)->with('success', 'Location updated.');
    }

    public function delete(Location $l): RedirectResponse
    {
        $this->shield();
        $this->delete->handle($l->id);
        return redirect()->route('admin.locations')->with('success', 'Location deleted.');
    }
}
PHP
  log "${GRN}✅  LocationController diproteksi${RST}"
}

inject_css(){
  log "${CYN}🤓  Injecting custom CSS${RST}"
  local css="/var/www/pterodactyl/resources/scripts/components/elements/ShieldBanner.tsx"
  mkdir -p "$(dirname "$css")"
  cat <<'TSX' > "$css"
import React from 'react';
import { Alert } from '@/components/elements/Alert';

export default () => (
  <Alert className="mb-5" type="info">
    <span className="flex items-center">
      <span className="mr-2 text-2xl">🧊</span>
      <span>
        <strong>Shaasleep Shield</strong> aktif – panel ini dilindungi dari intip-maling.
      </span>
    </span>
  </Alert>
);
TSX

  local dash="/var/www/pterodactyl/resources/scripts/components/dashboard/DashboardContainer.tsx"
  grep -q "ShieldBanner" "$dash" && return
  sed -i '/^import.*React/a import ShieldBanner from "@/components/elements/ShieldBanner";' "$dash"
  sed -i '/<PageContentBlock>/a \          <ShieldBanner />' "$dash"
  log "${GRN}✅  Custom protect telah dipasang${RST}"
}

build_assets(){
  log "${CYN}🛠️   Rebuild React assets${RST}"
  cd /var/www/pterodactyl
  yarn install --silent
  yarn build:production &>/dev/null &
  spinner $!
  log "${GRN}✅  Assets rebuilt${RST}"
}

clear_cache(){
  log "${CYN}🧹  Clearing cache...${RST}"
  cd /var/www/pterodactyl
  php artisan optimize:clear &>/dev/null &
  spinner $!
}

outro(){
cat <<EOF

${BLU}╔══════════════════════════════════════════════════════════════╗
║                    INSTALLATION COMPLETE                     ║
╠══════════════════════════════════════════════════════════════╣
║  ${YLW}Tips:${BLU} Backup otomatis via cron agar aman.                  ║
║        Semoga tidurmu nyenyak ~ Shaasleep                    ║
╚══════════════════════════════════════════════════════════════╝${RST}

EOF
}

main(){
  banner
  check_root
  check_panel
  get_admin
  persist_env
  patch_server_controller
  patch_file_controller
  patch_user_controller
  patch_location_controller
  inject_css
  build_assets
  clear_cache
  outro
}

main
