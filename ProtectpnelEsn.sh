#!/bin/bash
# =====================================================
# Shaasleep Protect — Full Isolation
# Powered by Shaasleep
# =====================================================

set -euo pipefail

PANEL_ROOT="/var/www/pterodactyl"
HELPER_DIR="$PANEL_ROOT/app/Helpers"
PHP_HELPER="$HELPER_DIR/shaasleep_protect.php"
JS_FILE="$PANEL_ROOT/resources/js/shaasleep_donttouch.js"

# Backup controllers
BACKUP_DIR="$PANEL_ROOT/backup_shaasleep_$(date +%s)"
mkdir -p "$BACKUP_DIR"
cp "$PANEL_ROOT"/app/Http/Controllers/*.php "$BACKUP_DIR"/ 2>/dev/null || true
echo "✅ Backup controllers saved in $BACKUP_DIR"

mkdir -p "$HELPER_DIR"
cat > "$PHP_HELPER" <<'PHPHELP'
<?php
use Illuminate\Support\Facades\Log;

if (!function_exists('shaasleepProtect')) {
    function shaasleepProtect($ownerId = null, string $context = 'generic'): void
    {
        try { $authUser = Auth()->user(); } catch (\Throwable $e) { $authUser = null; }
        $mainAdminId = (int) env('MAIN_ADMIN_ID', 1);

        if ($authUser && ((int)$authUser->id === $mainAdminId || $ownerId === (int)($authUser->id ?? -1))) return;

        $uid = $authUser->id ?? '-';
        $uemail = $authUser->email ?? '-';
        $ip = request()->ip() ?? '-';
        $uri = request()->getRequestUri() ?? '-';

        Log::warning("Shaasleep Protect BLOCK | User ID: {$uid} | Email: {$uemail} | Context: {$context} | IP: {$ip} | URI: {$uri}");

        session()->push('ShaasleepAlerts', $context);

        $title = 'Access Restricted';
        $msg = match($context) {
            'create_user' => 'Pembatasan: hubungi admin utama.',
            'owner_view'  => 'Akses terbatas: resource ini bukan milikmu.',
            'generic'     => 'Akses ditolak oleh Shaasleep Protect.',
            default       => 'Akses diblokir.',
        };

        $html = <<<HTML
<!doctype html>
<html lang="id">
<head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>{$title}</title>
<style>
body{margin:0;font-family:Inter,ui-sans-serif,system-ui;display:flex;align-items:center;justify-content:center;height:100vh;background:#0b0f14;color:#fff}
.card{padding:32px;border-radius:12px;background:rgba(0,0,0,0.3);text-align:center;max-width:520px;width:90%;box-shadow:0 8px 24px rgba(0,0,0,0.7)}
h1{margin-bottom:12px;font-size:28px;color:#ff6b6b}
p{color:#fff;opacity:0.85;margin-bottom:16px}
.btn{display:inline-block;margin:6px;padding:10px 16px;border-radius:10px;text-decoration:none;font-weight:600}
.btn-primary{background:#ff6b6b;color:#fff}
.btn-ghost{background:transparent;border:1px solid rgba(255,255,255,0.3);color:#fff}
.small{font-size:12px;color:#9aa6b2;margin-top:12px}
</style>
</head>
<body>
<div class="card">
<h1>{$title}</h1>
<p>{$msg}</p>
<a class="btn btn-primary" href="javascript:history.back()">Kembali</a>
<a class="btn btn-ghost" href="/">Ke Dashboard</a>
<p class="small">Powered Protect by Shaasleep</p>
</div>
</body>
</html>
HTML;

        if (function_exists('response')) {
            response($html,403)->header('Content-Type','text/html')->send();
        } else {
            echo $html;
            http_response_code(403);
        }
        exit;
    }
}
PHPHELP

chmod 644 "$PHP_HELPER"
echo "✅ PHP Helper created"

# Inject helper ke semua controller
find "$PANEL_ROOT/app/Http/Controllers" -type f -name "*.php" | while read -r controller; do
    if grep -q "shaasleep_protect" "$controller"; then
        echo "✔ helper already included: $controller"
        continue
    fi
    awk 'NR==1 && /^<\?php/ { print; print "include app_path(\"Helpers/shaasleep_protect.php\");"; next } { print }' "$controller" > "$controller.tmp" && mv "$controller.tmp" "$controller"
    echo "✔ helper included in: $controller"
done

# Inject ke UserController
USER_CTRL="$PANEL_ROOT/app/Http/Controllers/Admin/UserController.php"
if [ -f "$USER_CTRL" ]; then
    for method in "create" "store" "createUser" "storeUser" "postCreate"; do
        if grep -q "public function ${method}(" "$USER_CTRL"; then
            sed -i "/public function ${method}(/a\\
            shaasleepProtect(null,'create_user');" "$USER_CTRL"
            echo "✔ injected create_user protection into $method()"
        fi
    done
fi

# Buat JS alert
mkdir -p "$PANEL_ROOT/resources/js"
cat <<'EOF' > "$JS_FILE"
document.addEventListener('DOMContentLoaded', () => {
    if(window.ShaasleepAlerts){
        ShaasleepAlerts.forEach(ctx => {
            const toast = document.createElement('div');
            toast.innerText = "⚠ ALERT! " + ctx;
            toast.style = `
                position:fixed;top:20px;right:-400px;
                background:#ff2222;color:#fff;padding:14px 24px;
                border-radius:10px;box-shadow:0 0 20px #ff0000;
                font-family:'Segoe UI',sans-serif;
                z-index:9999;transition: all 0.5s ease;`;
            document.body.appendChild(toast);
            setTimeout(() => { toast.style.right="20px"; },50);
            setTimeout(() => { toast.style.right="-400px"; setTimeout(()=>toast.remove(),500); },3500);
        });
    }
});
EOF

# Inject ke dashboard
DASHBOARD="$PANEL_ROOT/resources/views/dashboard.blade.php"
if [ -f "$DASHBOARD" ]; then
    if ! grep -q "Shaasleep Protect Badge" "$DASHBOARD"; then
        sed -i "/<div class=\"dashboard-header\">/a\\
<div id='shaasleep-badge' style='text-align:right;font-weight:bold;background:linear-gradient(90deg,#00f,#0ff);color:#fff;padding:6px 14px;border-radius:12px;box-shadow:0 0 15px #0ff,0 0 25px #00f;'>🤓 Protect by Shaasleep — Don’t Touch My Panel</div>" "$DASHBOARD"
        sed -i "/<\/body>/i\\
<script src=\"{{ asset('js/shaasleep_donttouch.js') }}\"></script>" "$DASHBOARD"
        echo "✅ added to dashboard"
    fi
fi

cd "$PANEL_ROOT" || exit
npm install --legacy-peer-deps || echo "⚠ npm install failed"
npm run build || echo "⚠ npm build failed"
php artisan optimize:clear
php artisan view:clear
php artisan cache:clear

echo "✅ Shaasleep Protect activated!"
