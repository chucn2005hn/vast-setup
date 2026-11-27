# ==================================================================
#  VAST SCAN - quet mang, liet ke cac may Ubuntu/Vast va trang thai
#  Chay tren Windows (CMD):
#    powershell -ExecutionPolicy Bypass -File %USERPROFILE%\vast_scan.ps1
#  - Tu tim dai mang (vd 192.168.1.x), ping ca dai, doc bang ARP
#  - Vao tung may bang SSH key (khong hoi mat khau) lay: card, Vast, port, ID
#  - Nho lai MAC -> IP: may nao DOI IP se bao "DOI IP (cu: ...)"
#  - Dat ten cho may (de nho): them -DatTen
#    powershell -ExecutionPolicy Bypass -File %USERPROFILE%\vast_scan.ps1 -DatTen
#  - Hoi Vast.ai (API key) xem may nao BAO LOI tren web: loi port, bi an,
#    offline, doi IP mang. Lan dau hoi API key (luu tai %USERPROFILE%\vast_apikey.txt)
#    Doi key: them -DoiKey   |   Chi quet mang LAN, khong hoi Vast: them -KhongVast
#  - Xem TAT CA thong tin Vast cua 1 may (de gui ho tro / tim loi): them -ChiTiet 157941
#  - May LAN khop voi ID tren Vast nho TEN MAY: tren moi may chay 1 lan
#      sudo bash vast_setup_rtx.sh ten     (moi may 1 ten KHAC NHAU -> hien o dong "Name" tren web)
# ==================================================================
param([string]$User = "lehien", [string]$Prefix = "", [switch]$DatTen, [switch]$DoiKey, [switch]$KhongVast, [string]$ChiTiet = "")

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
if nvidia-smi -L >/dev/null 2>&1; then
  g=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | sed 's/NVIDIA GeForce //;s/NVIDIA //' | sort | uniq -c | awk '{c=$1;$1="";printf "%sx%s ",c,$0}')
  w=$(nvidia-smi --query-gpu=pcie.link.width.current,pcie.link.width.max --format=csv,noheader,nounits 2>/dev/null | awk -F', *' '{printf "x%s%s ",$1,($1<$2?"(LOI)":"")}')
else
  n=$(lspci 2>/dev/null | grep -ciE '(vga|3d).*nvidia')
  w=""
  if pgrep -f qemu-system >/dev/null 2>&1; then g="${n} card: DANG CHAY MAY AO (VM)"
  elif ls /sys/bus/pci/drivers/vfio-pci 2>/dev/null | grep -q ':'; then g="${n} card: KET CHE DO VM"
  elif [ "${n:-0}" -gt 0 ]; then g="${n} card: DRIVER LOI"
  else g="KHONG THAY CARD"; fi
fi
v=$(systemctl is-active vastai 2>/dev/null)
p=$(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null)
i=$(cat /etc/vast-info 2>/dev/null | tr '\n' ' ')
m=$(cat /sys/class/net/$(ip route show default | awk '{print $5; exit}')/address 2>/dev/null)
u=$(curl -4 -s -m 5 api.ipify.org 2>/dev/null || wget -qO- -T 5 api.ipify.org 2>/dev/null)
echo "VASTINFO|$(hostname)|$g|$v|$p|$i|$m|$(uptime -p)|$w|$u"
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
    $db[$_.MAC] = [pscustomobject]@{ Ten = $_.Ten; MAC = $_.MAC; IP = $_.IP; TrangThai = $_.TrangThai; Card = $_.Card; Port = $_.Port; ID = $_.ID; Host = $_.Host; IPMang = $_.IPMang; LastSeen = $_.LastSeen }
  }
}

$rows = @()
foreach ($ip in ($macOf.Keys | Sort-Object { [int]($_ -replace '.*\.', '') })) {
  $mac = $macOf[$ip]
  if ($ip -eq $myIP) { continue }
  $row = [ordered]@{ Ten = ""; IP = $ip; MAC = $mac; TrangThai = ""; Card = ""; PCIe = ""; Port = ""; ID = ""; IPMang = ""; GhiChu = ""; Host = "" }
  if ($ip -match '\.1$') { $row.TrangThai = "modem"; $rows += [pscustomobject]$row; continue }

  if (Test-Port22 $ip) {
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=no -o "UserKnownHostsFile=$nullKH" -o LogLevel=ERROR "$User@$ip" "echo $b64 | base64 -d | bash" 2>$null
    $info = $out | Where-Object { $_ -like "VASTINFO|*" } | Select-Object -First 1
    if ($info) {
      $f = $info.Split('|')
      if ($f[6]) { $mac = $f[6].Trim().ToLower(); $row.MAC = $mac }
      $row.Host = $f[1].Trim()
      $row.Card = $f[2].Trim()
      if ($f.Count -gt 8) { $row.PCIe = $f[8].Trim(); if ($row.PCIe -match "LOI") { $row.GhiChu = "CARD CHAY THIEU LANE -> het khach: chuyen card sang khe x16" } }
      if ($row.Card -match "MAY AO") { $row.GhiChu = "card dang o may ao: co khach thue VM? xem web (#Running) - KHONG khoi dong lai" }
      elseif ($row.Card -match "KET CHE DO VM") { $row.GhiChu = "card ket o che do VM, khong co may ao -> het khach: sudo reboot" }
      elseif ($row.Card -match "DRIVER LOI") { $row.GhiChu = "driver khong nhan card -> het khach: sudo reboot; van loi: cam lai card" }
      elseif ($row.Card -match "KHONG THAY CARD") { $row.GhiChu = "may khong thay card -> tat may, cam lai card + day nguon 8-pin" }
      $row.Port = $f[4].Trim()
      if ($f.Count -gt 9) { $row.IPMang = $f[9].Trim() }
      if ($f[5] -match 'ID=(\d+)') { $row.ID = $Matches[1] }
      if ($f[5] -match 'NAME=([^?\s]+)') { $row.Ten = $Matches[1] }
      if (-not $row.Ten -and $row.Host -and $row.Host -ne $User) { $row.Ten = $row.Host }
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
    if ($old.IP -ne $ip) { $row.GhiChu = ("DOI IP (cu: $($old.IP)) -> sua DHCP Binding + Port Forwarding; " + $row.GhiChu).Trim("; ") }
    if (-not $row.ID -and $old.ID) { $row.ID = $old.ID }
    if (-not $row.Port -and $old.Port) { $row.Port = $old.Port }
    if (-not $row.Ten -and $old.Ten) { $row.Ten = $old.Ten }
    if (-not $row.Host -and $old.Host) { $row.Host = $old.Host }
  } elseif ($mac -ne "?" -and $row.TrangThai -notmatch "khong phai|modem") {
    if (-not $row.GhiChu) { $row.GhiChu = "may moi thay lan dau" }
  }
  $rows += [pscustomobject]$row
}

# ---- 5a. May cu bien mat + may moi CUNG DAI PORT = cung 1 o cung, doi main/doi MAC
$seenNow = @{}; foreach ($r in $rows) { $seenNow[$r.MAC] = $true }
$replaced = @{}
foreach ($old in @($db.Values)) {
  if ($seenNow.ContainsKey($old.MAC) -or -not $old.Port -or $old.Port -eq "?" -or -not "$($old.IP)".StartsWith("$Prefix.")) { continue }
  $r = $rows | Where-Object { $_.Port -eq $old.Port -and $_.MAC -ne $old.MAC -and (-not $old.IPMang -or -not $_.IPMang -or $old.IPMang -eq $_.IPMang) } | Select-Object -First 1
  if (-not $r) { continue }
  $r.GhiChu = ("DOI MAIN + DOI IP (cu: $($old.IP)) -> modem: DHCP Binding + Port Forwarding $($r.Port) ve IP nay -> sudo bash vast_setup_rtx.sh doimay; " + ($r.GhiChu -replace 'may moi thay lan dau', '')).Trim("; ")
  if (-not $r.ID -and $old.ID) { $r.ID = $old.ID }
  if (-not $r.Ten -and $old.Ten) { $r.Ten = $old.Ten }
  $replaced[$old.MAC] = $true
}

# ---- 5b. Hoi Vast.ai: may nao dang bao loi tren web --------------
$vast = @()
$keyFile = Join-Path $homeDir "vast_apikey.txt"
if (-not $KhongVast) {
  $key = ""
  if ((Test-Path $keyFile) -and -not $DoiKey) { $key = (Get-Content $keyFile -Raw).Trim() }
  if (-not $key) {
    Write-Host "Dan API key Vast (https://cloud.vast.ai/manage-keys/) de xem loi tren web. Enter = bo qua:" -ForegroundColor Cyan
    $key = (Read-Host "API key").Trim()
    if ($key) { Set-Content -Path $keyFile -Value $key -Encoding ASCII }
  }
  if ($key) {
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $resp = $null
      try { $resp = Invoke-RestMethod -Uri "https://console.vast.ai/api/v0/machines/?owner=me" -Headers @{ Authorization = "Bearer $key" } -TimeoutSec 30 }
      catch { $resp = Invoke-RestMethod -Uri "https://console.vast.ai/api/v0/machines?owner=me&api_key=$key" -TimeoutSec 30 }
      $list = if ($resp.machines) { $resp.machines } else { @($resp) }
      if ($ChiTiet) {
        $one = $list | Where-Object { "$($_.id)" -eq $ChiTiet.Trim() } | Select-Object -First 1
        if ($one) { Write-Host "=== CHI TIET MAY $ChiTiet (copy gui ho tro / gui Claude) ===" -ForegroundColor Cyan; $one | Format-List * | Out-String -Width 250 | Write-Host }
        else { Write-Host "Khong thay may $ChiTiet trong tai khoan" -ForegroundColor Yellow }
      }
      $hostCnt = @{}
      foreach ($m in $list) { $h = "$($m.hostname)".ToLower(); if ($h) { $hostCnt[$h] = 1 + [int]$hostCnt[$h] } }
      foreach ($m in $list) {
        $mid = "$($m.id)"; if (-not $mid) { continue }
        $errs = @()
        foreach ($pr in $m.PSObject.Properties) {
          if ($pr.Name -notmatch 'err|issue|warn|problem' -or $pr.Name -match 'interrupt') { continue }
          $val = $pr.Value
          if ($null -eq $val) { continue }
          $txt = if ($val -is [string] -or $val -is [ValueType]) { "$val" } else { ($val | ConvertTo-Json -Compress -Depth 3) }
          if ($txt -match '^\s*(|0|False|false|null|\[\]|\{\})\s*$') { continue }
          if ($txt -match '^\s*-?[0-9.]+\s*$') { continue }   # chi la con so, khong phai cau bao loi
          if ($txt.Length -gt 120) { $txt = $txt.Substring(0, 120) + "..." }
          $errs += $txt
        }
        $rel = if ($m.reliability2) { [math]::Round([double]$m.reliability2 * 100, 1) } elseif ($m.reliability) { [math]::Round([double]$m.reliability * 100, 1) } else { "" }
        $apiHost = "$($m.hostname)".Trim()
        $pubIP = "$($m.public_ipaddr)".Trim()
        $uniq = $apiHost -and ($apiHost -ne $User) -and ($hostCnt[$apiHost.ToLower()] -eq 1)
        $lan = $rows | Where-Object { $_.ID -eq $mid } | Select-Object -First 1
        if (-not $lan -and $uniq) {
          $lan = $rows | Where-Object { $_.Host -eq $apiHost -and -not $_.ID -and $_.TrangThai -eq "DA CAI VAST" -and (-not $_.IPMang -or -not $pubIP -or $_.IPMang -eq $pubIP) } | Select-Object -First 1
          if ($lan) { $lan.ID = $mid }
        }
        if (-not $lan) { $lan = $db.Values | Where-Object { $_.ID -eq $mid } | Select-Object -First 1 }
        if (-not $lan -and $uniq) { $lan = $db.Values | Where-Object { $_.Host -and $_.Host -eq $apiHost } | Select-Object -First 1 }
        $vast += [pscustomobject]@{
          ID = $mid; TenWeb = $apiHost; Ten = $(if ($lan) { $lan.Ten } else { "" }); IPLan = $(if ($lan) { $lan.IP } else { "?" })
          Card = "$($m.num_gpus)x $($m.gpu_name)"; IPMang = "$($m.public_ipaddr)"
          Listed = $(if ($m.listed) { "co" } else { "KHONG" }); TinCay = $rel
          LoiTrenWeb = ($errs -join " | ")
        }
        if ($lan -and ($rows -contains $lan)) {
          if ($errs) { $lan.GhiChu = (("VAST BAO LOI: " + ($errs -join " | ")) + "; " + $lan.GhiChu).Trim("; ") }
          if ($lan.IPMang -and $m.public_ipaddr -and $lan.IPMang -ne "$($m.public_ipaddr)") { $lan.GhiChu = ("IP MANG DOI (Vast: $($m.public_ipaddr), may: $($lan.IPMang)) -> chay  sudo bash vast_setup_rtx.sh web; " + $lan.GhiChu).Trim("; ") }
        }
      }
    } catch {
      Write-Host "Khong hoi duoc Vast ($($_.Exception.Message)). Key sai/het han -> chay lai voi -DoiKey" -ForegroundColor Yellow
    }
  }
}

# ---- 6. In ket qua -----------------------------------------------
Write-Host ""
Write-Host "=== MAY TRONG MANG LAN ($Prefix.x) ===" -ForegroundColor Cyan
$rows | Format-Table -AutoSize Ten, IP, MAC, TrangThai, Card, PCIe, Port, ID, IPMang, GhiChu | Out-String -Width 300 | Write-Host

if ($vast) {
  Write-Host "=== TAT CA MAY TREN VAST.AI (ca may o mang khac) ===" -ForegroundColor Cyan
  $vast | Sort-Object ID | Format-Table -AutoSize ID, TenWeb, Ten, IPLan, Card, IPMang, Listed, TinCay, LoiTrenWeb | Out-String -Width 300 | Write-Host
  $bad = @($vast | Where-Object { $_.LoiTrenWeb -or $_.Listed -eq "KHONG" })
  if ($bad.Count -gt 0) {
    Write-Host "CO $($bad.Count) MAY CAN XU LY:" -ForegroundColor Red
    foreach ($b in $bad) {
      $why = if ($b.LoiTrenWeb) { $b.LoiTrenWeb } else { "chua list / bi an" }
      Write-Host ("  - May {0} {1} (LAN {2}, mang {3}): {4}" -f $b.ID, $(if ($b.Ten) { $b.Ten } elseif ($b.TenWeb -ne $User) { $b.TenWeb } else { "" }), $b.IPLan, $b.IPMang, $why) -ForegroundColor Red
    }
    Write-Host "  Loi PORT / Networking -> xem may do co 'DOI IP' o bang tren khong; vao modem sua DHCP Binding + Port Forwarding" -ForegroundColor Yellow
    Write-Host "     dung IP LAN moi, dung dai port; kiem tra https://portchecker.co (IP mang + 1 port trong dai) phai Open;" -ForegroundColor Yellow
    Write-Host "     xong SSH vao may chay:  sudo bash vast_setup_rtx.sh web" -ForegroundColor Yellow
  } else {
    Write-Host "Vast khong bao loi may nao." -ForegroundColor Green
  }
  if (@($vast | Where-Object { $_.IPLan -eq "?" }).Count -gt 0) {
    Write-Host "May co 'IPLan ?' = chua biet la may nao trong LAN (may o cho khac, hoac nhieu may trung ten 'lehien')." -ForegroundColor DarkGray
    Write-Host "  -> SSH vao TUNG may chay 1 lan:  sudo bash vast_setup_rtx.sh ten   (moi may 1 ten KHAC NHAU, vd 3060-50)" -ForegroundColor DarkGray
  }
}

$seen = @{}; foreach ($r in $rows) { $seen[$r.MAC] = $true }
$missing = $db.Values | Where-Object { -not $seen.ContainsKey($_.MAC) -and -not $replaced.ContainsKey($_.MAC) -and $_.TrangThai -match "VAST|Ubuntu" }
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
foreach ($k in @($replaced.Keys)) { $db.Remove($k) }
foreach ($r in $rows) {
  if ($r.MAC -eq "?" -or $r.TrangThai -match "khong phai|modem") { continue }
  $db[$r.MAC] = [pscustomobject]@{ Ten = $r.Ten; MAC = $r.MAC; IP = $r.IP; TrangThai = $r.TrangThai; Card = $r.Card; Port = $r.Port; ID = $r.ID; Host = $r.Host; IPMang = $r.IPMang; LastSeen = $now }
}
$db.Values | Export-Csv -NoTypeInformation -Encoding UTF8 $dbFile
Write-Host "Da luu danh sach may: $dbFile" -ForegroundColor DarkGray
Write-Host "SSH vao may: ssh $User@<IP>   |   May 'DOI IP' -> sua DHCP Binding + Port Forwarding tren modem" -ForegroundColor DarkGray
