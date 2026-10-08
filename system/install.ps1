#requires -RunAsAdministrator
<#
.SYNOPSIS
    Post-install lockdown for a Windows 11 IoT Enterprise college/student PC.

.DESCRIPTION
    Creates/normalizes a local account named "student" with a blank password and
    standard-user privileges, then applies per-user restrictions to that account.

    The script also configures UAC so standard-user elevation requests are
    automatically denied. This UAC setting is device-wide because Windows exposes
    it as a computer security policy.

.NOTES
    Run from an elevated 64-bit PowerShell session.

    A blank-password account is intentionally requested. Treat this as a
    physically controlled lab/kiosk account and keep a separate administrative
    account for maintenance.

    A reboot/logoff is recommended after the script completes.
#>

[CmdletBinding()]
param(
    [switch]$Restart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StudentName = 'student'
$LogRoot     = Join-Path $env:ProgramData 'CollegePC'
$LogFile     = Join-Path $LogRoot 'student-lockdown.log'

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
Start-Transcript -Path $LogFile -Append | Out-Null

function Get-BuiltInGroupNameFromSid {
    param(
        [Parameter(Mandatory)]
        [string]$Sid
    )

    $sidObject = New-Object System.Security.Principal.SecurityIdentifier($Sid)
    try {
        return $sidObject.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
    }
    catch {
        return $null
    }
}

function Set-PolicyDword {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$Value
    )

    New-Item -Path $Path -Force | Out-Null
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Set-PolicyString {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Value
    )

    New-Item -Path $Path -Force | Out-Null
    New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value $Value -Force | Out-Null
}

function Test-IsAdministrator {
    $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

try {
    Write-Host '=== College PC student lockdown ===' -ForegroundColor Cyan

    if (-not (Test-IsAdministrator)) {
        throw 'This script must be run as Administrator.'
    }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    Write-Host "Detected OS: $($os.Caption) / build $($os.BuildNumber)" -ForegroundColor DarkGray

    if ($os.Caption -notmatch 'IoT Enterprise') {
        Write-Warning 'The detected edition is not Windows 11 IoT Enterprise. The script will continue, but verify your image before production use.'
    }

    # -------------------------------------------------------------------------
    # 1. Create or normalize the student account.
    # -------------------------------------------------------------------------
    $student = Get-LocalUser -Name $StudentName -ErrorAction SilentlyContinue

    if (-not $student) {
        Write-Host "Creating local account '$StudentName' with no password..."
        $student = New-LocalUser `
            -Name $StudentName `
            -NoPassword `
            -AccountNeverExpires
    }
    else {
        Write-Host "Account '$StudentName' already exists; normalizing it..."
        Enable-LocalUser -Name $StudentName
        Set-LocalUser -Name $StudentName -AccountNeverExpires $true
    }

    # Force the account to have a blank password, even if a previous
    # installation already created "student" with a password.
    $netOutput = & net.exe user $StudentName "" /passwordreq:no 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not set '$StudentName' to a blank password: $($netOutput -join ' ')"
    }

    # Do not allow the student to set a password later.
    Set-LocalUser -Name $StudentName -UserMayChangePassword $false

    # Resolve the SID once; it is used for both the profile and verification.
    $ntAccount = New-Object System.Security.Principal.NTAccount("$env:COMPUTERNAME\$StudentName")
    $studentSid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
    Write-Host "Student SID: $studentSid" -ForegroundColor DarkGray

    # The Users group is the normal baseline for interactive standard users.
    $usersGroup = Get-BuiltInGroupNameFromSid -Sid 'S-1-5-32-545'
    if (-not $usersGroup) {
        throw 'Could not resolve the built-in Users group.'
    }

    $usersMembers = @(Get-LocalGroupMember -Group $usersGroup -ErrorAction SilentlyContinue)
    if (-not ($usersMembers | Where-Object { $_.SID.Value -eq $studentSid })) {
        Add-LocalGroupMember -Group $usersGroup -Member "$env:COMPUTERNAME\$StudentName"
        Write-Host "Added '$StudentName' to '$usersGroup'."
    }

    # Remove the student from built-in privileged/sensitive local groups.
    $groupsToStrip = @(
        'S-1-5-32-544', # Administrators
        'S-1-5-32-547', # Power Users
        'S-1-5-32-548', # Account Operators
        'S-1-5-32-549', # Server Operators
        'S-1-5-32-550', # Print Operators
        'S-1-5-32-551', # Backup Operators
        'S-1-5-32-552', # Replicator
        'S-1-5-32-555', # Remote Desktop Users
        'S-1-5-32-556', # Network Configuration Operators
        'S-1-5-32-557', # Incoming Forest Trust Builders
        'S-1-5-32-558', # Performance Monitor Users
        'S-1-5-32-559'  # Performance Log Users
    ) | Select-Object -Unique

    foreach ($groupSid in $groupsToStrip) {
        $groupName = Get-BuiltInGroupNameFromSid -Sid $groupSid
        if (-not $groupName) {
            continue
        }

        $members = @(Get-LocalGroupMember -Group $groupName -ErrorAction SilentlyContinue)
        if ($members | Where-Object { $_.SID.Value -eq $studentSid }) {
            try {
                Remove-LocalGroupMember -Group $groupName -Member "$env:COMPUTERNAME\$StudentName" -Confirm:$false
                Write-Host "Removed '$StudentName' from '$groupName'."
            }
            catch {
                Write-Warning "Could not remove '$StudentName' from '$groupName': $($_.Exception.Message)"
            }
        }
    }

    # -------------------------------------------------------------------------
    # 2. Create the student's profile without needing a first interactive logon.
    # -------------------------------------------------------------------------
    if (-not ('CollegePC.UserProfileNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace CollegePC {
    public static class UserProfileNative {
        [DllImport("userenv.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int CreateProfile(
            [MarshalAs(UnmanagedType.LPWStr)] string pszUserSid,
            [MarshalAs(UnmanagedType.LPWStr)] string pszUserName,
            [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszProfilePath,
            uint cchProfilePath
        );
    }
}
'@
    }

    $profilePath = Join-Path $env:SystemDrive "Users\$StudentName"

    if (-not (Test-Path -LiteralPath $profilePath)) {
        Write-Host "Creating profile for '$StudentName'..."
        $profileBuffer = New-Object System.Text.StringBuilder 260
        $hr = [CollegePC.UserProfileNative]::CreateProfile(
            $studentSid,
            $StudentName,
            $profileBuffer,
            [uint32]$profileBuffer.Capacity
        )

        if ($hr -ne 0 -and -not (Test-Path -LiteralPath $profilePath)) {
            $hexHr = ('0x{0:X8}' -f ([uint32]$hr))
            throw "CreateProfile failed with HRESULT $hexHr."
        }

        if ($profileBuffer.Length -gt 0) {
            $profilePath = $profileBuffer.ToString()
        }
    }

    $studentHiveFile = Join-Path $profilePath 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $studentHiveFile)) {
        throw "Student profile hive was not found at '$studentHiveFile'."
    }

    # -------------------------------------------------------------------------
    # 3. Apply per-user shell restrictions directly to the student's hive.
    # -------------------------------------------------------------------------
    $tempHiveName = 'CollegePC_Student'
    $tempHiveRoot = "Registry::HKEY_USERS\$tempHiveName"

    # If the hive is already mounted, unload our temporary name first.
    & reg.exe unload "HKU\$tempHiveName" 2>$null | Out-Null

    Write-Host "Applying per-user lockdown policies..."

    $loadResult = & reg.exe load "HKU\$tempHiveName" "$studentHiveFile" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not load the student registry hive. reg.exe said: $($loadResult -join ' ')"
    }

    try {
        $explorerPolicy = "$tempHiveRoot\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
        $systemPolicy   = "$tempHiveRoot\Software\Microsoft\Windows\CurrentVersion\Policies\System"

        # No Control Panel / Settings.
        Set-PolicyDword  -Path $explorerPolicy -Name 'NoControlPanel' -Value 1
        Set-PolicyString -Path $explorerPolicy -Name 'SettingsPageVisibility' -Value 'hide:*'

        # Remove easy launch paths to shells/tools.
        Set-PolicyDword -Path $explorerPolicy -Name 'NoRun' -Value 1
        Set-PolicyDword -Path $explorerPolicy -Name 'NoWinKeys' -Value 1

        # Disable Task Manager, registry tools, and password changes.
        Set-PolicyDword -Path $systemPolicy -Name 'DisableTaskMgr'        -Value 1
        Set-PolicyDword -Path $systemPolicy -Name 'DisableRegistryTools'  -Value 1
        Set-PolicyDword -Path $systemPolicy -Name 'DisableChangePassword' -Value 1

        # DisableCMD is a different Windows policy location.
        $cmdPolicy = "$tempHiveRoot\Software\Policies\Microsoft\Windows\System"
        Set-PolicyDword -Path $cmdPolicy -Name 'DisableCMD' -Value 2

        # Additional process-name blocking for common admin/configuration tools.
        # This is a user-shell policy and is intentionally limited to the
        # student account rather than being written under HKLM.
        $disallowPath = "$explorerPolicy\DisallowRun"
        Set-PolicyDword -Path $explorerPolicy -Name 'DisallowRun' -Value 1
        New-Item -Path $disallowPath -Force | Out-Null

        $blockedProcesses = @(
            'taskmgr.exe',
            'regedit.exe',
            'reg.exe',
            'cmd.exe',
            'powershell.exe',
            'pwsh.exe',
            'powershell_ise.exe',
            'wt.exe',
            'mmc.exe',
            'control.exe',
            'systemsettings.exe',
            'msconfig.exe',
            'msinfo32.exe',
            'netplwiz.exe',
            'rstrui.exe',
            'gpupdate.exe',
            'schtasks.exe',
            'sc.exe',
            'net.exe',
            'net1.exe',
            'secedit.exe',
            'dism.exe',
            'diskpart.exe',
            'manage-bde.exe',
            'pnputil.exe',
            'msiexec.exe',
            'mshta.exe',
            'wscript.exe',
            'cscript.exe',
            'certutil.exe',
            'icacls.exe',
            'takeown.exe',
            'wbemtest.exe',
            'wusa.exe',
            'optionalfeatures.exe',
            'ComputerDefaults.exe'
        )

        $index = 1
        foreach ($processName in $blockedProcesses) {
            New-ItemProperty -Path $disallowPath -Name ([string]$index) -PropertyType String -Value $processName -Force | Out-Null
            $index++
        }

        Write-Host "Per-user restrictions applied to '$StudentName'."
    }
    finally {
        & reg.exe unload "HKU\$tempHiveName" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'The student registry hive could not be unloaded cleanly. Reboot before allowing the student account to log on.'
        }
    }

    # -------------------------------------------------------------------------
    # 4. Device-wide UAC hardening for standard users.
    # -------------------------------------------------------------------------
    # Microsoft documents this as a device-scoped security policy. Value 0
    # means "Automatically deny elevation requests" for standard users.
    $uacPolicy = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

    Write-Host 'Configuring UAC to automatically deny standard-user elevation...'
    Set-PolicyDword -Path $uacPolicy -Name 'EnableLUA'               -Value 1
    Set-PolicyDword -Path $uacPolicy -Name 'ConsentPromptBehaviorUser' -Value 0
    Set-PolicyDword -Path $uacPolicy -Name 'PromptOnSecureDesktop'   -Value 1

    # Do not allow installer detection to produce the "enter an admin password"
    # path for legacy installers on a student desktop.
    Set-PolicyDword -Path $uacPolicy -Name 'EnableInstallerDetection' -Value 0

    # -------------------------------------------------------------------------
    # 5. Refresh Group Policy where possible.
    # -------------------------------------------------------------------------
    Write-Host 'Refreshing local policy...'
    & gpupdate.exe /target:computer /force | Out-Null
    & gpupdate.exe /target:user /force | Out-Null

    # -------------------------------------------------------------------------
    # 6. Verification.
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '=== Verification ===' -ForegroundColor Cyan

    $studentCheck = Get-LocalUser -Name $StudentName
    Write-Host ("Account exists:             {0}" -f [bool]$studentCheck)
    Write-Host ("Enabled:                    {0}" -f $studentCheck.Enabled)
    Write-Host ("Password required:          {0}" -f $studentCheck.PasswordRequired)
    Write-Host ("Student SID:                {0}" -f $studentSid)

    $adminGroup = Get-BuiltInGroupNameFromSid -Sid 'S-1-5-32-544'
    $isAdmin = @(Get-LocalGroupMember -Group $adminGroup -ErrorAction SilentlyContinue) |
        Where-Object { $_.SID.Value -eq $studentSid }

    Write-Host ("In local Administrators:    {0}" -f [bool]$isAdmin)

    $uacValue = (Get-ItemProperty -Path $uacPolicy -Name 'ConsentPromptBehaviorUser').ConsentPromptBehaviorUser
    Write-Host ("UAC standard-user action:   {0} (0 = auto deny)" -f $uacValue)

    Write-Host ''
    Write-Host 'Lockdown installed.' -ForegroundColor Green
    Write-Host 'The student account is a standard user. Windows UAC will automatically deny elevation requests for standard users on this PC.'
    Write-Host 'Task Manager, Settings/Control Panel, registry tools, shells, and common administration utilities are blocked for the student account.'
    Write-Host ''
    Write-Host 'A reboot/logoff is recommended before handing the PC to students.' -ForegroundColor Yellow

    if ($Restart) {
        Write-Host 'Restarting in 10 seconds...'
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
        # Ignore transcript shutdown errors.
    }
}
