Import-Module GroupPolicy
Import-Module ActiveDirectory

# Prompt for license mode
$licmode = Read-Host "Enter licensing mode (User or Device)"
$liccode = if ($licmode -eq "User") { 4 } elseif ($licmode -eq "Device") { 2 } else { throw "Invalid mode. Use 'User' or 'Device'" }

# Prompt for license server
$licsrv = Read-Host "Enter Licensing Server IP or FQDN"

# Prompt for AD computers (browse with GUI)
Add-Type -AssemblyName System.Windows.Forms
$searcher = New-Object DirectoryServices.DirectorySearcher
$searcher.Filter = "(objectClass=computer)"
$searcher.PageSize = 1000
$computers = $searcher.FindAll() | ForEach-Object {
    $_.Properties["name"]
}
$form = New-Object System.Windows.Forms.Form
$form.Text = "Select Computers for RDP Enable"
$form.Width = 400
$form.Height = 500

$listBox = New-Object System.Windows.Forms.CheckedListBox
$listBox.Width = 360
$listBox.Height = 400
$listBox.Location = '10,10'
$listBox.SelectionMode = 'MultiExtended'
$listBox.Items.AddRange($computers)

$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Location = '150,420'
$okButton.Add_Click({ $form.Close() })

$form.Controls.Add($listBox)
$form.Controls.Add($okButton)
$form.ShowDialog()

$rdpenabled = $listBox.CheckedItems

# Create and configure GPO
$gpoName = "RDP Configuration Policy"
$gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $gpoName
}

# Allow log on through Remote Desktop Services
$rdUsersSid = "S-1-5-32-555"  # Remote Desktop Users group SID
Set-GPRegistryValue -Name $gpo.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "UserAuthentication" -Type DWord -Value 0
Set-GPRegistryValue -Name $gpo.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" -ValueName "fDenyTSConnections" -Type DWord -Value 0
Set-GPRegistryValue -Name $gpo.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -ValueName "SecurityLayer" -Type DWord -Value 0

# Set license mode and license server
Set-GPRegistryValue -Name $gpo.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\Licensing Core" -ValueName "LicensingMode" -Type DWord -Value $liccode
Set-GPRegistryValue -Name $gpo.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\Licensing Core" -ValueName "LicenseServers" -Type MultiString -Value @($licsrv)

# Configure User Rights Assignment for RDP and local logon
$rdUsers = @("BUILTIN\Remote Desktop Users")
$localUsers = @("BUILTIN\Users", "BUILTIN\Administrators")
Set-GPPrivilege -Name $gpoName -Privilege "SeRemoteInteractiveLogonRight" -Accounts $rdUsers
Set-GPPrivilege -Name $gpoName -Privilege "SeInteractiveLogonRight" -Accounts $localUsers

# Link GPO to selected computers' OUs
foreach ($comp in $rdpenabled) {
    $adComp = Get-ADComputer $comp
    $ouDn = ($adComp.DistinguishedName -split ",",2)[1]
    New-GPLink -Name $gpo.DisplayName -Target "OU=$ouDn" -Enforced:$false -ErrorAction SilentlyContinue
}

Write-Host "`n✅ GPO '$gpoName' configured and linked to selected computers."
