#!/bin/bash
# ------------------------------------------------------------------
#  painel blindado – verde-amarelo vibes  (c) 2025  @Shaasleep
# ------------------------------------------------------------------
set -euo pipefail

BLD='\e[1m'
RST='\e[0m'
c(){ echo "\e[38;5;$1m"; }
GRN=$(c 34)
YEL=$(c 226)
BLU=$(c 27)
WHI=$(c 255)

banner(){
clear
cat <<EOF
${GRN}╔══════════════════════════════════════════════════════╗
║                                                      ║
║     ${YEL}▗▄▄▖▗▖  ▗▖▗▄▄▄▖▗▄▄▖ ▗▄▖ ▗▄▄▖▗▄▄▄▖${GRN}            ║
║     ${YEL}▐▌  ▐▛▚▞▜▌  █ ▐▌  ▐▌ ▐▌▐▌   █ ${GRN}              ║
║     ${YEL}▐▌  ▐▌  ▐▌  █ ▐▌  ▐▛▜▌▐▌   █ ${GRN}              ║
║     ${YEL}▝▚▄▖▐▌  ▐▌  █ ▝▚▄▖▐▌ ▐▌▝▚▄▖ █ ${GRN}              ║
║                                                      ║
║     ${BLU}sleep tight – host tight${GRN}                     ║
║                                                      ║
╚══════════════════════════════════════════════════════╝${RST}
EOF
}

spin(){
  local p=$1; local d=0.08; local s='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  while kill -0 "$p" 2>/dev/null;do
    for i in $(seq 0 9);do printf "${YEL}${BLD}${s:$i:1}${RST} ";sleep $d;printf '\b\b';done
  done
}

root_ck(){ [[ $EUID -eq 0 ]] || { echo " root only";exit 1;}; }
panel_ck(){ [[ -d "/var/www/pterodactyl" ]] || { echo " panel not found";exit 1;}; }

get_id(){
  read -rp " admin id ❯ " AID
  [[ "$AID" =~ ^[0-9]+$ ]] || { echo " numbers only";exit 1;}
}

lock_env(){
  local e="/var/www/pterodactyl/.env"
  grep -q "^SHIELD_ID=" "$e" \
    && sed -i "s/^SHIELD_ID=.*/SHIELD_ID=$AID/" "$e" \
    || echo "SHIELD_ID=$AID" >> "$e"
}

seal_controllers(){
  for type in Server File;do
    local f="/var/www/pterodactyl/app/Http/Controllers/Api/Client/Server/${type}Controller.php"
    grep -q "shieldLock" "$f" && continue
    sed -i '/public function index(/a\
        /* shieldLock */\
        $u=auth()->user();if($u->id!='$AID'&&(int)$server->owner_id!==(int)$u->id)abort(403,"🟢 shield:on");' "$f"
  done

  # admin controllers
  printf '<?php
namespace Pterodactyl\\Http\\Controllers\\Admin;
use Illuminate\\Http\\RedirectResponse;use Illuminate\\View\\View;
use Pterodactyl\\Http\\Controllers\\Controller;
use Pterodactyl\\Http\\Requests\\Admin\\UserFormRequest;
use Pterodactyl\\Http\\Requests\\Admin\\LocationFormRequest;
use Pterodactyl\\Services\\Users\\UserUpdateService;
use Pterodactyl\\Services\\Locations\\{LocationCreationService,LocationUpdateService,LocationDeletionService};
use Pterodactyl\\Models\\Location;use Illuminate\\Support\\Facades\\Auth;
class UserController extends Controller{public function __construct(private UserUpdateService $s){}public function update(UserFormRequest $r,$u):RedirectResponse{if(Auth::user()->id!=env("SHIELD_ID"))throw new \\Exception("🟢 shield:on");$this->s->handle($u,$r->normalize());return redirect()->route("admin.users.view",$u->id);}}
class LocationController extends Controller{public function __construct(private LocationCreationService $c,private LocationUpdateService $u,private LocationDeletionService $d){}private function lock(){if(Auth::user()->id!=env("SHIELD_ID"))abort(403,"🟢 shield:on");}public function index():View{$this->lock();return view("admin.locations.index",["locations"=>Location::with("nodes")->get()]);}public function create(LocationFormRequest $r):RedirectResponse{$this->lock();$l=$this->c->handle($r->normalize());return redirect()->route("admin.locations.view",$l->id);}public function update(LocationFormRequest $r,Location $l):RedirectResponse{$this->lock();$this->u->handle($l->id,$r->normalize());return redirect()->route("admin.locations.view",$l->id);}public function delete(Location $l):RedirectResponse{$this->lock();$this->d->handle($l->id);return redirect()->route("admin.locations");}}' > "/var/www/pterodactyl/app/Http/Controllers/Admin/ShieldControllers.php"
}

inject_css(){
  local css="/var/www/pterodactyl/resources/scripts/assets/css/shield.css"
  cat <<'CSS' > "$css"
:root{
  --verde:#009739;
  --amarelo:#ffdf00;
  --azul:#012169;
}
body{
  background:linear-gradient(135deg,var(--azul) 0%,var(--verde) 50%,var(--amarelo) 100%);
  background-attachment:fixed;
}
.bg-neutral-800{
  background:rgba(0,25,60,.75)!important;
  backdrop-filter:blur(8px);
  border:1px solid rgba(255,223,0,.25);
  border-radius:1rem;
}
button{
  transition:all .2s ease;
}
button:hover{
  transform:translateY(-2px);
  box-shadow:0 8px 20px rgba(0,151,57,.45);
}
CSS
  local app="/var/www/pterodactyl/resources/scripts/app.tsx"
  grep -q "shield.css" "$app" || echo 'import "@/assets/css/shield.css";' >> "$app"
}

inject_banner(){
  local cmp="/var/www/pterodactyl/resources/scripts/components/elements/ShieldBanner.tsx"
  mkdir -p "$(dirname "$cmp")"
  cat <<'TSX' > "$cmp"
import React from 'react';
import { Alert } from '@/components/elements/Alert';
export default () => (
  <Alert className="mb-4 rounded-xl shadow-lg border-l-4 border-yellow-400">
    <div className="flex items-center gap-3">
      <span className="text-3xl">🕊️</span>
      <div>
        <div className="font-bold text-green-200">Painel Blindado</div>
        <div className="text-xs text-yellow-100">proteção verde-amarela ativa</div>
      </div>
    </div>
  </Alert>
);
TSX
  local dash="/var/www/pterodactyl/resources/scripts/components/dashboard/DashboardContainer.tsx"
  grep -q "ShieldBanner" "$dash" && return
  sed -i '/^import.*React/a import ShieldBanner from "@/components/elements/ShieldBanner";' "$dash"
  sed -i '/<PageContentBlock>/a \          <ShieldBanner />' "$dash"
}

build(){
  cd /var/www/pterodactyl
  yarn install --silent
  yarn build:production &>/dev/null &
  spin $!
}

clear_cache(){
  cd /var/www/pterodactyl
  php artisan optimize:clear &>/dev/null &
  spin $!
}

banner
root_ck
panel_ck
get_id
lock_env
seal_controllers
inject_css
inject_banner
build
clear_cache
echo -e "${GRN}done — id ${YEL}${AID}${GRN} locked${RST}  ${BLD}${WHI}@Shaasleep${RST}"
