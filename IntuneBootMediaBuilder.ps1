﻿<#
.SYNOPSIS
	Creates a bootable USB media or ISO file using the Windows ADK Preinstallation Environment (PE).

.DESCRIPTION
	This script creates a Intune installation media by downloading original installation sources from Microsoft an injecting configuration files to 
    create a fully unattended Autopilot installation.
	It integrates drivers and components and adds a custom startup script that runs when the PE boots. 
	The final image can be saved as an ISO file or written directly to a USB stick. It is designed specifically for Intune Autopilot deployments.
	A "binschonda.txt" file will be created in your Working Directory (The ones with DATE-RND name). if you want multiple Environments, remove that file.
    At the moment Hyper-V VMs with Windwos 11 will not work if you have TPM enabled and did not enable the workarround for incompatibilitys in the autounattend.xml

	- The script requires administrative privileges.
	- A USB stick with at least 8 GB of storage is required.
	- The ADK version should match the installed Windows version.

.NOTES

	Version:		1.0
	Author: 		Thomas Hoins 
					Datagroup OIT
 	initial Date:	10.12.2024
 	Changes: 		07.01.2025 first fully functional version

.LINK
	[IntuneInstall](https://github.com/ThomasHoins/IntuneInstall)

.COMPONENT
	Requires Modules Microsoft.Graph.Authentication

.PARAMETER PEPath
Specifies the path where the PE files will be cached.

.PARAMETER IsoPath
Specifies the target path for the ISO file. If no path is provided, the ISO will be saved in the working directory.

.PARAMETER WindowsVersion
Specifies the Windows Version, to extract from the install.wim.

.PARAMETER DownloadISO
Specifies the the source, where the installation ISO will be downloaded. If not supplied, it will try to use the FIDO Tool to download one from Microsoft.

.PARAMETER TempFolder
Specifies the path to the temporary folder. Default is `C:\Temp`.

.PARAMETER OutputFolder
Specifies the target folder where the final image will be saved.

.PARAMETER StartScriptSource
Specifies the URL of the startup script to be downloaded and executed by the PE.

.PARAMETER DriverFolder
Specifies the source folder for drivers to be injected into the PE image.

.PARAMETER AutounattendFile
Specifies the path to the autounattend.xml.
There is an excellent online generator for that file.
"https://schneegans.de/windows/unattend-generator/"

.PARAMETER ADKPath
Specifies the installation path of the Windows ADK. If the ADK is not installed, it will be downloaded and installed automatically.
The ADK will only be used if an ISO file is created or if you select a custom install image with the `-DownloadISO` parameter.

.PARAMETER ADKVersion
Specifies the version of the Windows ADK to be installed. The default is `10.1.22621.1`. This version should match the version of the installed operating system.

.PARAMETER TenantID
Specifies the Tenant ID of your Entra ID.
This can be acquired at the Overview page of your Entra.

.PARAMETER ProfileID
Specifies the ProfileID that is required to select the Autopilot Profile. Can be acquired with the following command after connecting to Graph:
(Invoke-MGGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles" -Method Get).Value

.PARAMETER InstallLanguage
Specifies the language for the installation. Default is "English".
Arabic, Brazilian Portuguese, Bulgarian, Chinese (Simplified), Chinese (Traditional), 
Croatian, Czech, Danish, Dutch, English, English International, Estonian, Finnish, 
French, French Canadian, German, Greek, Hebrew, Hungarian, Italian, Japanese, Korean, 
Latvian, Lithuanian, Norwegian, Polish, Portuguese, Romanian, Russian, Serbian Latin, 
Slovak, Slovenian, Spanish, Spanish (Mexico), Swedish, Thai, Turkish, Ukrainian	

.PARAMETER WindowsEdition
Specifies the Windows edition to download. Default is "Windows 11 Home/Pro/Edu".

.PARAMETER AutocreateWifiProfile
Specifies whether to automatically create a Wi-Fi profile. Default is $true.

.PARAMETER MultiParitionUSB
Specifies whether to create multiple partitions on the USB stick. Default is $false.

.PARAMETER AppId
Specifies the Application ID for authentication.

.PARAMETER AppSecret
Specifies the Application Secret for authentication.

.INPUTS
This script does not accept piped inputs.

.OUTPUTS
The script creates either a bootable USB media or an ISO file.

.EXAMPLE
PS> .\IntuneBootMediaBuilder.ps1 -PEPath "C:\WinPE" -IsoPath "C:\Images\Boot.iso" -DriverFolder "C:\Drivers"

Creates an ISO file with the integrated PE image and drivers.

.EXAMPLE
PS> .\IntuneBootMediaBuilder.ps1 -TempFolder "D:\Temp" -OutputFolder "D:\Output" -StartScriptSource "https://example.com/Start.ps1"

Uses custom temp and output folders and downloads a custom startup script.

.EXAMPLE
PS> .\IntuneBootMediaBuilder.ps1 -PEPath "C:\WinPE" -DriverFolder "C:\Drivers" -ADKVersion "10.1.22000.1"

Creates a PE image using a specified ADK version.

#>

#Requires -Modules Microsoft.Graph.Authentication

Param (
	[string]$PEPath,
	[string]$IsoPath,
	[string]$DownloadISO, #="https://software.download.prss.microsoft.com/dbazure/Win11_24H2_English_x64.iso?t=23e54b6a-020f-4f2b-ae70-e1e52676ea1c&P1=1734172137&P2=601&P3=2&P4=QToZDn6aVi4krTph%2fkSVvhS9RPAacWYuSb54K3mwuNrDZ6Vkh%2bil6BjCeoqf9bvAXns96krwYEbFjFiqocRaYNiGewxgN0YWFUKIttmo%2fVNNRKoXBlnlIy0omYT1ljweXzYUU17cJXEq3vtVHKT45mxVqbgainFJEDr%2brpEjK32FsfBIPG9FTvrl8dESy%2bhZ1KFyw7N0FXCXt1CaLipsfvkV49fr4a0EYnnVsIzDPIB1Cxpv9rSeOVtYchsPpWufYuq88cGH0tuyJWrK5IrHvDGbjnwBuQtX9WQ7dYPwdIwU7WYoH4SYh3%2fGnDbMfnGQMY4j7ap0qpE%2bIT4cuMriBA%3d%3d",
	[string]$InstallLanguage = "English", 
	[string]$Locale = "en-US", #en-US, de-DE, fr-FR, es-ES, it-IT, ja-JP, ko-KR, zh-CN, Override the default Locale
	[string]$WindowsEdition = "Windows 11 Home/Pro/Edu", #Download Edition	
	[string]$WindowsVersion = "Windows 11 Pro",	
	[string]$AutocreateWifiProfile = $true,
	[string]$TempFolder = "C:\Temp",
	[string]$OutputFolder,
	[bool]$MultiParitionUSB = $false,
	[string]$StartScriptSource = "https://raw.githubusercontent.com/ThomasHoins/IntuneInstall/refs/heads/main/Start.ps1",
	[string]$DriverFolder = "C:\Temp\Drivers",
	[string]$AutounattendFile,
	[string]$ADKPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit",
	[string]$ADKVersion = "10.1.22621.1",
	[string]$TenantID = "22c3b957-8768-4139-8b5e-279747e3ecbf",
	[string]$AppId = "31f7ef0c-9662-4522-bb32-f1b8c2d5a7c3",
	[string]$AppSecret = "b_u8Q~kVtK6Es0BAmtvB~wq4pvfWoY1vVUGnTahX",
	[string]$ProfileID = "41b669f0-86d4-4363-b666-5046469d0611"
)	

###########################################################
#	Functions
###########################################################

function Clear-Path {
	# Clean Up
	Write-Host "Cleaning up files"
	Get-WindowsImage -Mounted | Dismount-WindowsImage -Discard -ErrorAction SilentlyContinue
	Disconnect-MgGraph -ErrorAction SilentlyContinue
	If ($PEPath) { Remove-Item $PEPath -Recurse -Force -ErrorAction SilentlyContinue}
	If ($BootPath) { Remove-Item $BootPath -Recurse -Force -ErrorAction SilentlyContinue}
	If ($InstMediaPath) { Remove-Item $InstMediaPath -Recurse -Force -ErrorAction SilentlyContinue}
	If ($InstWimTemp) { Remove-Item $InstWimTemp -Recurse -Force -ErrorAction SilentlyContinue}
}

function Get-IntuneJson() {
	[cmdletbinding()]
	<#
	.SYNOPSIS
	Gets the Intune Profile and converts it to JSON
	
	.DESCRIPTION
	Input the Profile ID and get back the JSON to include to you installation
	
	.PARAMETER id
	Specifies the Profile ID to use for the installation

	.EXAMPLE
	Get-IntuneJson -id $ID

	.Notes
	Extracted  from here:
	https://github.com/andrew-s-taylor/public/blob/main/Powershell%20Scripts/Intune/create-windows-iso-with-apjson.ps1
	
	-#>
	param
	(
		[string]$id
	
	)
	
	# Defining Variables
	$graphApiVersion = "beta"
	$Resource = "deviceManagement/windowsAutopilotDeploymentProfiles"
	$uri = "https://graph.microsoft.com/$graphApiVersion/$Resource/$id"
	$approfile = Invoke-MGGraphRequest -Uri $uri -Method Get -OutputType PSObject
	
	# Set the org-related info
	$script:TenantOrg = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/organization" -OutputType PSObject).value
	foreach ($domain in $script:TenantOrg.VerifiedDomains) {
		if ($domain.isDefault) {
			$script:TenantDomain = $domain.name
		}
	}
	$oobeSettings = $approfile.outOfBoxExperienceSettings
	
	# Build up properties
	$json = @{}
	$json.Add("Comment_File", "Profile $($approfile.displayName)")
	$json.Add("Version", 2049)
	$json.Add("ZtdCorrelationId", $approfile.id)
	if ($approfile."@odata.type" -eq "#microsoft.graph.activeDirectoryWindowsAutopilotDeploymentProfile") {
		$json.Add("CloudAssignedDomainJoinMethod", 1)
	}
	else {
		$json.Add("CloudAssignedDomainJoinMethod", 0)
	}
	if ($approfile.deviceNameTemplate) {
		$json.Add("CloudAssignedDeviceName", $approfile.deviceNameTemplate)
	}
	
	# Figure out config value
	$oobeConfig = 8 + 256
	if ($oobeSettings.userType -eq 'standard') {
		$oobeConfig += 2
	}
	if ($oobeSettings.hidePrivacySettings -eq $true) {
		$oobeConfig += 4
	}
	if ($oobeSettings.hideEULA -eq $true) {
		$oobeConfig += 16
	}
	if ($oobeSettings.skipKeyboardSelectionPage -eq $true) {
		$oobeConfig += 1024
		if ($_.language) {
			$json.Add("CloudAssignedLanguage", $_.language)
			# Use the same value for region so that screen is skipped too
			$json.Add("CloudAssignedRegion", $_.language)
		}
	}
	if ($oobeSettings.deviceUsageType -eq 'shared') {
		$oobeConfig += 32 + 64
	}
	$json.Add("CloudAssignedOobeConfig", $oobeConfig)
	
	# Set the forced enrollment setting
	if ($oobeSettings.hideEscapeLink -eq $true) {
		$json.Add("CloudAssignedForcedEnrollment", 1)
	}
	else {
		$json.Add("CloudAssignedForcedEnrollment", 0)
	}
	
	$json.Add("CloudAssignedTenantId", $script:TenantOrg.id)
	$json.Add("CloudAssignedTenantDomain", $script:TenantDomain)
	$embedded = @{}
	$embedded.Add("CloudAssignedTenantDomain", $script:TenantDomain)
	$embedded.Add("CloudAssignedTenantUpn", "")
	if ($oobeSettings.hideEscapeLink -eq $true) {
		$embedded.Add("ForcedEnrollment", 1)
	}
	else {
		$embedded.Add("ForcedEnrollment", 0)
	}
	$ztc = @{}
	$ztc.Add("ZeroTouchConfig", $embedded)
	$json.Add("CloudAssignedAadServerData", (ConvertTo-JSON $ztc -Compress))
	
	# Skip connectivity check
	if ($approfile.hybridAzureADJoinSkipConnectivityCheck -eq $true) {
		$json.Add("HybridJoinSkipDCConnectivityCheck", 1)
	}
	
	# Hard-code properties not represented in Intune
	$json.Add("CloudAssignedAutopilotUpdateDisabled", 1)
	$json.Add("CloudAssignedAutopilotUpdateTimeout", 1800000)
	
	# Return the JSON
	ConvertTo-JSON $json
}

###########################################################
#	Main
###########################################################
$startTime = Get-Date
$userPrincipal = (New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent()))
If (!($userPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))) {
	Write-Host "Admin permissions required!"
	Exit
}

Clear-Path

#create Path environment create new workdir if "binschonda.txt" does not exist
If (!(Test-Path -Path $TempFolder)) {
	New-Item -ItemType Directory -Path $TempFolder
}
$WorkPath = (Get-ChildItem -Path $TempFolder -Include binschonda.txt -File -Recurse -ErrorAction SilentlyContinue).DirectoryName
If (([string]::IsNullOrEmpty($WorkPath))) {
	$random = (Get-Random -Maximum 1000 ).ToString('0000')
	$date = (get-date -format yyyyMMddmmss).ToString()
	$TempPath = "$date-$random"
	$WorkPath = "$TempFolder\$TempPath"
	New-Item -ItemType Directory -Path $WorkPath
}	

#Add minimal Drivers from Repository
If (!(Test-Path -PathType Container $TempFolder\Drivers)) {
	$origProgressPreference = $ProgressPreference
	$ProgressPreference = 'SilentlyContinue' #to spped up the download significant
	Invoke-Webrequest "https://raw.githubusercontent.com/ThomasHoins/IntuneBootMediaBuilder/refs/heads/main/Drivers.zip" -Outfile "$TempFolder\Drivers.zip"
	$ProgressPreference = $origProgressPreference
	Expand-Archive -LiteralPath "$TempFolder\Drivers.zip" -DestinationPath $TempFolder
	Remove-Item "$TempFolder\Drivers.zip" -Force -ErrorAction SilentlyContinue
}	

If (([string]::IsNullOrEmpty($PEPath) )) {
	$PEPath = "$WorkPath\WinPE_admd64"	
}
If (([string]::IsNullOrEmpty($IsoPath) )) {
	$IsoPath = $WorkPath	
}
$BootPath = "$WorkPath\mount\Boot"
$InstWimPath = "$WorkPath\mount\InstWim"
$PackageTemp = "$WorkPath\mount\PackageTemp"

# prepare PE data
If (!([string]::IsNullOrEmpty($DownloadISO)) -or ($MediaSelection -eq "I")) {
	$env:DandIRoot = "$ADKPath\Deployment Tools"
	$env:WinPERoot = "$ADKPath\Windows Preinstallation Environment"
	$env:WinPERootNoArch = "$ADKPath\Windows Preinstallation Environment"
	$env:OSCDImgRoot = "$env:DandIRoot\$($env:PROCESSOR_ARCHITECTURE)\Oscdimg"
	Remove-Item $PEPath -Recurse -Force -ErrorAction SilentlyContinue
	$null=Start-Process -FilePath "$ADKPath\Windows Preinstallation Environment\copype.cmd" -ArgumentList amd64, $PEPath -NoNewWindow -Wait -PassThru
	Copy-Item "$ADKPath\Deployment Tools\amd64\Oscdimg\efisys_noprompt.bin" "$PEPath\fwfiles\efisys.bin" -Force
	Remove-Item "$PEPath\media\Boot\bootfix.bin" -Force 
}

# aquire Json Data from tenant
# If a Logon Profile with sufficient permissin is available we try to log on as application, otherwise we will be asked for credentials
If (!([string]::IsNullOrEmpty($AppId))-and !([string]::IsNullOrEmpty($AppSecret))) {
	$SecureClientSecret = ConvertTo-SecureString -String $AppSecret -AsPlainText -Force
	$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AppId, $SecureClientSecret
	# Connect to Microsoft Graph Using the Tenant ID and Client Secret Credential
	$null = Connect-MgGraph -TenantId $TenantID -ClientSecretCredential $ClientSecretCredential -NoWelcome
	}

If (!(Get-MgContext)){
	$null = Connect-MgGraph 
	$TenantID = (Get-MgContext).TenantId
}

$ProfileJSON = Get-IntuneJson -id $ProfileID

#Ask dor media type to build
$MediaSelection = Read-Host "Create an ISO image or a USB Stick or Cancel? [I,U]"

If ((get-disk | Where-Object bustype -eq 'usb').Size -lt 7516192768 -and $MediaSelection -eq "U") {
	Write-Host "This USB stick is too small!"
	Exit
} 

If (!([string]::IsNullOrEmpty($DownloadISO))-and $MediaSelection -eq "I") {
	If (!(Test-Path -Path "$ADKPath\Deployment Tools\DandISetEnv.bat")) {
		Write-Host "No ADK has been found, installing it!"
		winget install Microsoft.WindowsADK --version $ADKVersion
		winget install Microsoft.ADKPEAddon --version $ADKVersion
	}
}

###########################################################
#	Downloading Installation Media
###########################################################

#Get FIDO and download Windows 11 installation ISO
If ([string]::IsNullOrEmpty($DownloadISO) ) {
	Invoke-Webrequest "https://raw.githubusercontent.com/pbatard/Fido/refs/heads/master/Fido.ps1" -Outfile "$WorkPath\Fido.ps1"
	#you can only use the script 3 times and then you have to wait 24h, restrictions of the MS web page.
	if (Test-Path -PathType Leaf "$WorkPath\DownloadIso.txt") {
		If ((Get-Item "$WorkPath\DownloadIso.txt").CreationTime -gt (Get-Date).AddHours(-24)) {
			$DownloadISO = Get-Content "$WorkPath\DownloadIso.txt"
		}
		Else {
			$DownloadISO = & "$WorkPath\Fido.ps1" -Ed $WindowsEdition -Lang $InstallLanguage -geturl
			Out-File -FilePath "$WorkPath\DownloadIso.txt" -InputObject $DownloadISO
		}
	}
	Else {
		$DownloadISO = & "$WorkPath\Fido.ps1" -Ed $WindowsEdition -Lang $InstallLanguage -geturl
		Out-File -FilePath "$WorkPath\DownloadIso.txt" -InputObject $DownloadISO
	}
	Out-File -FilePath "$WorkPath\DownloadIso.txt" -InputObject $DownloadISO
	# Make window visible again
	Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
	[DllImport("user32.dll")]
	[return: MarshalAs(UnmanagedType.Bool)]
	public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
	$hwnd = (Get-Process -Id $PID).MainWindowHandle
	[WinAPI]::ShowWindow($hwnd, 1) | Out-Null
}

#Download the ISO file if not already present
If (!(Test-Path -PathType Leaf "$WorkPath\Installation.iso")) {
	Write-Host "Downloading installation ISO please be patient!" -ForegroundColor Red
	$Isostartime = Get-Date
	$origProgressPreference = $ProgressPreference
	$ProgressPreference = 'SilentlyContinue' #to spped up the download significant
	Invoke-Webrequest $DownloadISO -Outfile "$WorkPath\Installation.iso"
	$ProgressPreference = $origProgressPreference
	$Isoendtime = Get-Date
	$time = $Isoendtime - $Isostartime
	$FileSize = (Get-Item -Path "$WorkPath\Installation.iso").Length
	Write-Host "It took $($time.Hours)h:$($time.Minutes)m:$($time.Seconds)s to download the $($FileSize/1GB)GB  Image" -ForegroundColor Magenta
	New-Item "$WorkPath\binschonda.txt"
}

#Mount the ISO and copy the data to the InstMediaPath folder
If (Test-Path -PathType Leaf $WorkPath\Installation.iso) {
	$InstVol = Mount-DiskImage -ImagePath $WorkPath\Installation.iso | Get-Volume
	$InstDriveLetter = "$($InstVol.DriveLetter):"
	$VolName = $InstVol.FileSystemLabel
	$InstMediaPath = "$WorkPath\$VolName"
	Remove-Item $InstMediaPath -Recurse -Force -ErrorAction SilentlyContinue
	New-Item -ItemType Directory -Path $InstMediaPath
	Write-Host "Copying installation data to $InstMediaPath please be patient!" -ForegroundColor Red
	Start-Process "$($env:windir)\System32\Robocopy.exe" "/NP /s /z ""$InstDriveLetter"" ""$InstMediaPath""" -Wait -NoNewWindow
	Dismount-DiskImage -ImagePath $WorkPath\Installation.iso
}
Else {
	Write-Host "$WorkPath\Installation.iso  not found! Exiting"
	Clear-Path
	exit 1
}

###########################################################
#	Prepareing Boot Image
###########################################################

Write-Host "Preparing Boot Image"

# prepare directory f. PE
Remove-Item $BootPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $BootPath

# mount Boot Image
Write-Host "Mounting Boot Image"
$BootWimTemp = "$InstMediaPath\sources\Boot.wim"
Set-ItemProperty -Path $BootWimTemp -Name IsReadOnly -Value $false
Mount-WindowsImage -ImagePath $BootWimTemp -Index:2 -Path $BootPath

# Inject Drivers to BootImage
Write-Host "Adding drivers to Boot Image"
Add-WindowsDriver -Path $BootPath -Driver $DriverFolder -Recurse

# Add Components to BootImage
Write-Host "Adding components to Boot Image"
$Components = @("*WinPE-WMI*", "*WinPE-NetFX*", "*WinPE-Scripting*", "*WinPE-PowerShell*", "*WinPE-StorageWM*", "*WinPE-DismCmdlet*", "*WinPE-Dot3Svc*")
$ComponetsPaths = (Get-ChildItem -Path "$ADKPath\Windows Preinstallation Environment\amd64\WinPE_OCs\*" -include $Components).FullName
$ComponetsPathsEn = (Get-ChildItem -Path "$ADKPath\Windows Preinstallation Environment\amd64\WinPE_OCs\en-us\*" -include $Components).FullName

Remove-Item $PackageTemp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $PackageTemp

ForEach ($Path in $ComponetsPaths + $ComponetsPathsEn) {
	Copy-Item $Path $PackageTemp
} 
Add-WindowsPackage -Path $BootPath -PackagePath $PackageTemp -IgnoreCheck
Get-WindowsPackage -Path $BootPath | Format-Table -AutoSize | Out-File "$WorkPath\Components.txt"

# Add new Start Script to BootImage
Remove-Item "$BootPath\Windows\System32\startnet.cmd" -Force -ErrorAction SilentlyContinue
Remove-Item "$BootPath\Windows\System32\diskpart.txt" -Force -ErrorAction SilentlyContinue

$DiskpartScript = @"
select disk 0
clean
"@
Add-Content -Path "$BootPath\Windows\System32\diskpart.txt" -Value $DiskpartScript

$startnetText = @"
`@ ECHO OFF
FOR /F "tokens=*" %%g IN ('WMIC DISKDRIVE where Interfacetype="SCSI"') do (SET DISKID=%%g)
IF "%DISKID%"==0 (diskpart /s X:\Windows\System32\diskpart.txt)
powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 

ECHO "Unplug and replug USB Network adapter!"
ping 127.0.0.1 -n 20 >NUL


"X:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe" invoke-webrequest "$StartScriptSource" -Outfile X:\Users\Public\Downloads\Start.ps1
"X:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe" -Executionpolicy Bypass X:\Users\Public\Downloads\Start.ps1
wpeinit
"@

Add-Content -Path "$BootPath\Windows\System32\startnet.cmd" -Value $startnetText

# Unmount Boot Image
Dismount-WindowsImage -Path $BootPath -Save

###########################################################
#	Prepareing Install Image
###########################################################

Write-Host "Preparing Install Image"

# prepare directory f. Install.wim
Remove-Item $InstWimPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $InstWimPath

# mount Install Image
$InstWimTemp = "$InstMediaPath\sources\Install.wim"
$InstWimDest = "$InstMediaPath\sources\Dest.wim"
$InstallSWMFile = "$InstMediaPath\sources\Install.swm"
Set-ItemProperty -Path $InstWimTemp -Name IsReadOnly -Value $false
Mount-WindowsImage -ImagePath $InstWimTemp -Name $WindowsVersion -Path $InstWimPath
Write-Host "Adding drivers to Install Image"
Add-WindowsDriver -Path $InstWimPath -Driver $DriverFolder -Recurse


# inject Intune Profile
$ProfileJSON | Set-Content -Encoding Ascii "$InstWimPath\Windows\Provisioning\Autopilot\AutopilotConfigurationFile.json"

# Unmount Install Image
Dismount-WindowsImage -Path $InstWimPath -Save -CheckIntegrity
# Extract selected Windows Version
Export-WindowsImage -SourceImagePath $InstWimTemp -SourceName $WindowsVersion -DestinationImagePath $InstWimDest
Remove-Item $InstWimTemp -Force
Rename-Item $InstWimDest $InstWimTemp

#Add Installation Files to $InstMediaPath
Invoke-Webrequest "https://raw.githubusercontent.com/ThomasHoins/IntuneBootMediaBuilder/refs/heads/main/Settings.ps1" -Outfile "$InstMediaPath\Settings.ps1"
Invoke-Webrequest "https://raw.githubusercontent.com/ThomasHoins/IntuneBootMediaBuilder/refs/heads/main/UploadAutopilotInfo.ps1" -Outfile "$InstMediaPath\UploadAutopilotInfo.ps1"
Invoke-Webrequest "https://raw.githubusercontent.com/ThomasHoins/IntuneBootMediaBuilder/refs/heads/main/autounattend.xml" -Outfile "$InstMediaPath\autounattend.xml"

#Create Wifi Profile (only the first Profile will be exported)
If ($AutocreateWifiProfile) {
	$list=((netsh.exe wlan show profiles) -match ' : ')
	If($List.Count -ne 0) {
		$ProfileName=$List.Split(":")[1].Trim()
		$ProfileFile=((netsh wlan export profile $ProfileName key=clear folder="$InstMediaPath\") -split """")[5]
		$Name = ($ProfileFile.Split("\")[-1]).Replace(".xml","")
		$content = Get-Content "$InstMediaPath\Settings.ps1"
		$line = Get-Content "$InstMediaPath\Settings.ps1" | Select-String "Wifi =" | Select-Object -ExpandProperty Line
		$content = $content.Replace( $line, "[string]`$Wifi = ""$Name""") 
		Set-Content "$InstMediaPath\Settings.ps1" -Value $content
	}
	else {
		Write-Host "No Wifi Profile found!" -ForegroundColor Yellow
	}
}

#Add the $TenantId, $AppId, $AppSecret in the Setting with the values from parameters
$content = Get-Content "$InstMediaPath\Settings.ps1"
$line = Get-Content "$InstMediaPath\Settings.ps1" | Select-String "TenantId =" | Select-Object -ExpandProperty Line
$content = $content.Replace( $line, "[string]`$TenantId = ""$TenantID""") 
$line = Get-Content "$InstMediaPath\Settings.ps1" | Select-String "AppId =" | Select-Object -ExpandProperty Line
$content = $content.Replace( $line, "[string]`$AppId = ""$AppId""") 
$line = Get-Content "$InstMediaPath\Settings.ps1" | Select-String "AppSecret =" | Select-Object -ExpandProperty Line
$content = $content.Replace( $line, "[string]`$AppSecret = ""$AppSecret""") 
Set-Content "$InstMediaPath\Settings.ps1" -Value $content


###########################################################
#	Creating Installation Media
###########################################################

#Create Media
copy-item $AutounattendFile "$InstMediaPath" -Force
Switch ($MediaSelection) {
	I {
		#"$ADKPath\Deployment Tools\amd64\Oscdimg\oscdimg.exe" -bootdata:2#p0,e,b"$PEPath\fwfiles\etfsboot.com"#pEF,e,b"$PEPath\fwfiles\efisys.bin" -u1 -udfver102 "$InstMediaPath" "$IsoFileName"
		#"$ADKPath\Deployment Tools\amd64\Oscdimg\oscdimg.exe" -bootdata:2#p0,e,b"$PEPath\fwfiles\etfsboot.com"#pEF,e,b"$PEPath\fwfiles\efisys.bin" -u1 -udfver102 "$InstMediaPath" "$IsoFileName"
		# Test if all required files are there and create an Installation ISO
		if (!(Test-Path $IsoPath)) {
			New-Item -ItemType Directory -Path $IsoPath
		}
        $oscdimgCmd = "$ADKPath\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        if (!(Test-Path $oscdimgCmd)) {
            Write-Host "Could not locate $oscdimgCmd" -ForegroundColor Red
        }
		$IsoFileName = "$IsoPath\IntuneBootMedia.iso"
        if (!(Test-Path $InstMediaPath)) {
            Write-Host "Could not locate $ISOSourceFolder" -ForegroundColor Red
        }
        $etfsboot = "$PEPath\fwfiles\etfsboot.com"
        if (!(Test-Path $etfsboot)) {
            Write-Host "Could not locate $etfsboot" -ForegroundColor Red
        }
        $efisys = "$PEPath\fwfiles\efisys.bin"
        if (!(Test-Path $efisys)) {
            Write-Host "Could not locate $efisys" -ForegroundColor Red
        }

        Write-Host "Creating: $ISOFile" -ForegroundColor Cyan
        $data = '2#p0,e,b"{0}"#pEF,e,b"{1}"' -f $etfsboot, $efisys
        $null = Start-Process $oscdimgCmd -args @("-bootdata:$data",'-udfver102',"-u1","-l$VolName","`"$InstMediaPath`"", "`"$IsoFileName`"") -Wait -NoNewWindow


		# Check the result of the command
		if ((Test-Path $IsoFileName)) {
			Write-Host "The installation iso has been created succesfully and can be found here: $IsoPath " -ForegroundColor Green
		}
		Else{
			Write-Host "ERROR: Failed to create $IsoPath file." -ForegroundColor Red
			Clear-Path
		}
		
	}
	U {
		$usbDrive = (Get-Disk | Where-Object Path -like '*usbstor*')
		$usbDriveNumber = $usbDrive.Number
		Get-Partition $usbDriveNumber | Remove-Partition
		If ($MultiParitionUSB) {
			#rework this part, all Setup stuff has to go to I: !
			New-Partition $usbDriveNumber -Size 2048MB -IsActive -DriveLetter P | Format-Volume -FileSystem FAT32 -NewFileSystemLabel "WinPE" -Confirm:$false -Force
			New-Partition $usbDriveNumber -UseMaximumSize        -DriveLetter I | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Images" -Confirm:$false -Force
			Write-Host "Copying boot data to disk"
			Start-Process "$($env:windir)\System32\Robocopy.exe"  "/NP /s /z ""$InstMediaPath"" P: /max:3800000000" -Wait -NoNewWindow
			New-Item -ItemType Directory -Path "I:\Source"
			Write-Host "Copying Install.wim to disk"
			Copy-Item $InstWimTemp "I:\Source" -Force
		}
		Else {
			If ((get-disk | Where-Object bustype -eq 'usb').Size -lt 2199023255552) {
				New-Partition $usbDriveNumber -UseMaximumSize -IsActive -DriveLetter P | Format-Volume -FileSystem FAT32 -NewFileSystemLabel "WinPE" -Confirm:$false -Force
			}
			Else {
				New-Partition $usbDriveNumber -Size 2TB -IsActive -DriveLetter P | Format-Volume -FileSystem FAT32 -NewFileSystemLabel "WinPE" -Confirm:$false -Force
			}
			Set-ItemProperty -Path $InstWimTemp -Name IsReadOnly -Value $false
			#Split the install.wim if greater 4GiB
			If ((Get-Item $InstWimTemp).Length -gt 4294967295) {
				Split-WindowsImage -ImagePath "$InstWimTemp" -SplitImagePath $InstallSWMFile -FileSize 4096 -CheckIntegrity
				Remove-Item "$InstWimTemp" -Force
			}
			Start-Process "$($env:windir)\System32\Robocopy.exe"  "/NP /s /z ""$InstMediaPath"" P:" -Wait -NoNewWindow
		}
		Start-Process "$($env:windir)\System32\bootsect.exe" "/nt60 P: /force /mbr" -NoNewWindow -Wait
	}
}
$EndTime = Get-Date
Write-Host $startTime
Write-Host $EndTime
$time = $EndTime - $startTime
Write-Host "It Took $($time.Hours)h:$($time.Minutes)m:$($time.Seconds)s to Build this Media" -ForegroundColor Magenta
Write-Host "We are done!" -ForegroundColor Green
