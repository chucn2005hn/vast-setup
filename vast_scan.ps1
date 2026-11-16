# ==================================================================
#  VAST SCAN - quet mang, liet ke cac may Ubuntu/Vast va trang thai
#  Chay tren Windows (CMD):
#    powershell -ExecutionPolicy Bypass -File %USERPROFILE%\vast_scan.ps1
#  - Tu tim dai mang (vd 192.168.1.x), ping ca dai, doc bang ARP
#  - Vao tung may bang SSH key (khong hoi mat khau) lay: card, Vast, port, ID
#  - Nho lai MAC -> IP: may nao DOI IP se bao "DOI IP (cu: ...)"
#  - Dat ten cho may (de nho): them -DatTen
#    powershell -ExecutionPolicy Bypass -File %USERPROFILE%\vast_scan.ps1 -DatTen
# ==================================================================
param([string]$User = "lehien", [string]$Prefix = "", [switch]$DatTen)

$ErrorActionPreference = "SilentlyContinue"
$onWin = ($PSVersionTable.PSVersion.Major -le 5) -or $IsWindows
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$dbFile = Join-Path $homeDir "vast_may.csv"
$nullKH = if ($onWin) { "NUL" } else { "/dev/null" }

# ---- 1. Dai mang -------------------------------------------------
if (-not $Prefix) {
  foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
    if ($nic.OperationalStatus -ne "Up") { continue }
    $p = $nic.GetIPProperties()
    if (-not ($p.GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq "InterNetwork" })) { continue }
    $a = $p.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq "InterNetwork" } | Select-Object -First 1
    if ($a) { $Prefix = ($a.Address.ToString() -replace '\.\d+$', ''); $myIP = $a.Address.ToString(); break }
  }
}
if (-not $Prefix) { Write-Host "Khong tim thay mang. Chay lai: ... -Prefix 192.168.1" -ForegroundColor Red; exit 1 }
Write-Host "Dang quet $Prefix.1 - $Prefix.254 ..." -ForegroundColor Cyan

# ---- 2. Ping ca dai (song song) ----------------------------------
$tasks = @()
foreach ($i in 1..254) {
  try { $tasks += (New-Object System.Net.NetworkInformation.Ping).SendPingAsync("$Prefix.$i", 600) } catch {}
}
try { [System.Threading.Tasks.Task]::WaitAll($tasks) } catch {}
$alive = @{}
foreach ($t in $tasks) { try { if ($t.Result.Status -eq "Success") { $alive[$t.Result.Address.ToString()] = $true } } catch {} }

# ---- 3. Bang ARP (IP -> MAC) -------------------------------------
$macOf = @{}
$arp = if ($onWin) { arp -a } else { ip neigh }
foreach ($line in $arp) {
  if ($line -match '(\d+\.\d+\.\d+\.\d+)\s+.*?([0-9a-fA-F]{2}([-:][0-9a-fA-F]{2}){5})') {
    $ip = $Matches[1]; $mac = $Matches[2].ToLower().Replace('-', ':')
    if ($ip.StartsWith("$Prefix.") -and $mac -ne "ff:ff:ff:ff:ff:ff" -and -not $mac.StartsWith("01:00:5e")) { $macOf[$ip] = $mac }
  }
}
foreach ($ip in $alive.Keys) { if (-not $macOf.ContainsKey($ip)) { $macOf[$ip] = "?" } }

# ---- 4. Lenh chay tren may Ubuntu (khong can sudo) ---------------
$remote = @'
g=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | sed 's/NVIDIA GeForce //;s/NVIDIA //' | sort | uniq -c | awk '{c=$1;$1="";printf "%sx%s ",c,$0}')
v=$(systemctl is-active vastai 2>/dev/null)
p=$(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null)
i=$(cat /etc/vast-info 2>/dev/null | tr '\n' ' ')
m=$(cat /sys/class/net/$(ip route show default | awk '{print $5; exit}')/address 2>/dev/null)
echo "VASTINFO|$(hostname)|$g|$v|$p|$i|$m|$(uptime -p)"
'@ -replace "`r", ""
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))

function Test-Port22($ip) {
  $c = New-Object System.Net.Sockets.TcpClient
  try { $t = $c.ConnectAsync($ip, 22); return ($t.Wait(800) -and $c.Connected) } catch { return $false } finally { $c.Close() }
}

# ---- 5. Doc danh sach cu (de biet may nao doi IP) ----------------
$db = @{}
if (Test-Path $dbFile) {
  Import-Csv $dbFile | ForEach-Object {
    $db[$_.MAC] = [pscustomobject]@{ Ten = $_.Ten; MAC = $_.MAC; IP = $_.IP; TrangThai = $_.TrangThai; Card = $_.Card; Port = $_.Port; ID = $_.ID; LastSeen = $_.LastSeen }
  }
}

$rows = @()
foreach ($ip in ($macOf.Keys | Sort-Object { [int]($_ -replace '.*\.', '') })) {
  $mac = $macOf[$ip]
  if ($ip -eq $myIP) { continue }
  $row = [ordered]@{ Ten = ""; IP = $ip; MAC = $mac; TrangThai = ""; Card = ""; Port = ""; ID = ""; GhiChu = "" }
  if ($ip -match '\.1$') { $row.TrangThai = "modem"; $rows += [pscustomobject]$row; continue }

  if (Test-Port22 $ip) {
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=no -o "UserKnownHostsFile=$nullKH" -o LogLevel=ERROR "$User@$ip" "echo $b64 | base64 -d | bash" 2>$null
    $info = $out | Where-Object { $_ -like "VASTINFO|*" } | Select-Object -First 1
    if ($info) {
      $f = $info.Split('|')
      if ($f[6]) { $mac = $f[6].Trim().ToLower(); $row.MAC = $mac }
      $row.Card = $f[2].Trim()
      $row.Port = $f[4].Trim()
      if ($f[5] -match 'ID=(\d+)') { $row.ID = $Matches[1] }
      if ($f[5] -match 'NAME=([^?\s]+)') { $row.Ten = $Matches[1] }
      if ($f[5] -match 'PORTS=(\S+)' -and -not $row.Port) { $row.Port = $Matches[1] }
      $row.TrangThai = if ($f[3].Trim() -eq "active") { "DA CAI VAST" } elseif ($row.Card) { "Ubuntu, CHUA cai Vast" } else { "Ubuntu (khong thay card)" }
    } else {
      $row.TrangThai = "Co SSH nhung KHONG vao duoc bang key"
      $row.GhiChu = "may moi chua chay Lenh 1 / khoa khac"
    }
  } else {
    $row.TrangThai = "khong phai may Ubuntu"
  }

  if ($db.ContainsKey($mac)) {
    $old = $db[$mac]
    if ($old.IP -ne $ip) { $row.GhiChu = "DOI IP (cu: $($old.IP))" }
    if (-not $row.ID -and $old.ID) { $row.ID = $old.ID }
    if (-not $row.Port -and $old.Port) { $row.Port = $old.Port }
    if (-not $row.Ten -and $old.Ten) { $row.Ten = $old.Ten }
  } elseif ($mac -ne "?" -and $row.TrangThai -notmatch "khong phai|modem") {
    if (-not $row.GhiChu) { $row.GhiChu = "may moi thay lan dau" }
  }
  $rows += [pscustomobject]$row
}

# ---- 6. In ket qua -----------------------------------------------
Write-Host ""
$rows | Format-Table -AutoSize Ten, IP, MAC, TrangThai, Card, Port, ID, GhiChu | Out-String -Width 250 | Write-Host

$seen = @{}; foreach ($r in $rows) { $seen[$r.MAC] = $true }
$missing = $db.Values | Where-Object { -not $seen.ContainsKey($_.MAC) -and $_.TrangThai -match "VAST|Ubuntu" }
if ($missing) {
  Write-Host "KHONG THAY TREN MANG (tat may / mat mang / cam modem khac):" -ForegroundColor Yellow
  $missing | Format-Table -AutoSize Ten, IP, MAC, TrangThai, Card, Port, ID, LastSeen | Out-String -Width 250 | Write-Host
}

# ---- 6b. Dat ten (-DatTen) ---------------------------------------
if ($DatTen) {
  Write-Host "DAT TEN CHO MAY (Enter = giu ten cu / bo qua). Khong dau, khong cach, vd 2060-ke-trai" -ForegroundColor Cyan
  foreach ($r in $rows) {
    if ($r.TrangThai -match "khong phai|modem" -or $r.MAC -eq "?") { continue }
    $cur = if ($r.Ten) { " [dang: $($r.Ten)]" } else { "" }
    $n = Read-Host "  $($r.IP)  $($r.Card) $($r.TrangThai)$cur -> ten"
    if ($n) { $r.Ten = ($n.Trim() -replace '\s+', '-') }
  }
  Write-Host "Da dat ten. (Muon ten hien ca khi SSH: tren may chay  sudo bash vast_setup_rtx.sh ten)" -ForegroundColor DarkGray
}

# ---- 7. Luu lai ---------------------------------------------------
$now = Get-Date -Format "yyyy-MM-dd HH:mm"
foreach ($r in $rows) {
  if ($r.MAC -eq "?" -or $r.TrangThai -match "khong phai|modem") { continue }
  $db[$r.MAC] = [pscustomobject]@{ Ten = $r.Ten; MAC = $r.MAC; IP = $r.IP; TrangThai = $r.TrangThai; Card = $r.Card; Port = $r.Port; ID = $r.ID; LastSeen = $now }
}
$db.Values | Export-Csv -NoTypeInformation -Encoding UTF8 $dbFile
Write-Host "Da luu danh sach may: $dbFile" -ForegroundColor DarkGray
Write-Host "SSH vao may: ssh $User@<IP>   |   May 'DOI IP' -> sua DHCP Binding + Port Forwarding tren modem" -ForegroundColor DarkGray
