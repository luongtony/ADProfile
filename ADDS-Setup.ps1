# ==== FUNCTIONS ====

function Is-DomainJoined {
    return ([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain() -ne $null) -and $true
}

function Is-DomainController {
    return (Get-WindowsFeature AD-Domain-Services).InstallState -eq "Installed" -and (Get-ADDomainController -ErrorAction SilentlyContinue)
}

function Prompt-NetworkInterface {
    Write-Host "Available Network Interfaces:" -ForegroundColor Cyan
    Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Format-Table -AutoSize -Property ifIndex, Name, Status, MacAddress, LinkSpeed
    $IfIndex = Read-Host "Enter the ifIndex of the NIC to configure"
    $Interface = Get-NetAdapter | Where-Object { $_.ifIndex -eq [int]$IfIndex }
    if (-not $Interface) {
        throw "Invalid interface index."
    }
    return $Interface.Name
}

# ==== STEP 1: INITIAL PROMPTS ====

$InterfaceAlias = Prompt-NetworkInterface

$NewHostname    = Read-Host "Enter new hostname (leave blank to skip renaming)"
$IPAddress      = Read-Host "Enter static IP address (e.g., 192.168.1.20)"
$PrefixLength   = Read-Host "Enter subnet prefix length (e.g., 24)"
$Gateway        = Read-Host "Enter default gateway (e.g., 192.168.1.1)"
$DNSServersRaw  = Read-Host "Enter DNS servers (comma-separated, e.g., 192.168.1.10)"
$DNSServers     = $DNSServersRaw -split "," | ForEach-Object { $_.Trim() }

$DomainName     = Read-Host "Enter domain name (e.g., corp.local)"
$DomainUser     = Read-Host "Enter domain user (e.g., administrator)"
$DomainPass     = Read-Host "Enter domain user password" -AsSecureString
$DSRMPwd        = Read-Host "Enter DSRM password for promotion" -AsSecureString

$DomainCred     = New-Object PSCredential "$DomainName\$DomainUser", $DomainPass

# ==== STEP 2: SET STATIC IP ====
try {
    New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway -ErrorAction Stop
    Write-Host "Static IP configured."
} catch {
    Write-Warning "Static IP may already be set. Continuing..."
}
try {
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DNSServers -ErrorAction Stop
    Write-Host "DNS servers configured."
} catch {
    Write-Warning "DNS servers may already be configured. Continuing..."
}

# ==== STEP 3: RENAME HOST ====
if ($NewHostname -ne "") {
    try {
        Rename-Computer -NewName $NewHostname -Force -ErrorAction Stop
        Write-Host "Rebooting to apply hostname change: $NewHostname..." -ForegroundColor Yellow
        Restart-Computer -Force
        return
    } catch {
        Write-Warning "Rename failed or already applied. Continuing..."
    }
}

# ==== STEP 4: JOIN DOMAIN ====
if (-not (Is-DomainJoined)) {
    try {
        Write-Host "Joining domain $DomainName..." -ForegroundColor Cyan
        Add-Computer -DomainName $DomainName -Credential $DomainCred -Force -ErrorAction Stop
        Write-Host "Rebooting to complete domain join..." -ForegroundColor Yellow
        Restart-Computer -Force
        return
    } catch {
        Write-Warning "Domain join failed or already complete. Continuing..."
    }
} else {
    Write-Host "Already joined to a domain. Continuing..."
}

# ==== STEP 5: INSTALL AD DS ROLE ====
if (-not (Is-DomainController)) {
    try {
        Write-Host "Installing AD DS Role..." -ForegroundColor Cyan
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
    } catch {
        Write-Warning "AD DS role may already be installed. Continuing..."
    }

    # ==== STEP 6: PROMOTE TO DC ====
    try {
        Write-Host "Promoting to Domain Controller..." -ForegroundColor Cyan
        Install-ADDSDomainController `
            -DomainName $DomainName `
            -InstallDns:$true `
            -Credential $DomainCred `
            -DatabasePath "C:\Windows\NTDS" `
            -LogPath "C:\Windows\NTDS" `
            -SysvolPath "C:\Windows\SYSVOL" `
            -SafeModeAdministratorPassword $DSRMPwd `
            -Force:$true
    } catch {
        Write-Warning "DC promotion may have already been completed or failed."
    }
} else {
    Write-Host "This server is already a Domain Controller. Nothing more to do." -ForegroundColor Green
}
