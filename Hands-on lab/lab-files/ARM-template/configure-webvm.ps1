param (
    [Parameter(Mandatory=$False)] [string] $SqlIP = "",
    [Parameter(Mandatory=$False)] [string] $SqlPass = "",
    [Parameter(Mandatory = $true)]
    [string]
    $AzureUserName,

    [string]
    $AzurePassword,

    [string]
    $ODLID,

    [string]
    $InstallCloudLabsShadow,

    [string]
    $DeploymentID,
    
     [string]
  $AzureTenantID,
  
  [string]
  $AzureSubscriptionID,
  
     [string]
$AzureSubscriptionID,
  
  [string]
  $AzureTenantID
)

Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt -Append

$vmAdminUsername="demouser"
$trainerUserName="trainer"
$trainerUserPassword="Password.!!1"

function Wait-Install {
    $msiRunning = 1
    $msiMessage = ""
    while($msiRunning -ne 0)
    {
        try
        {
            $Mutex = [System.Threading.Mutex]::OpenExisting("Global\_MSIExecute");
            $Mutex.Dispose();
            $DST = Get-Date
            $msiMessage = "An installer is currently running. Please wait...$DST"
            Write-Host $msiMessage 
            $msiRunning = 1
        }
        catch
        {
            $msiRunning = 0
        }
        Start-Sleep -Seconds 1
    }
}

#Import Common Functions
$path = pwd
$path=$path.Path
$commonscriptpath = "$path" + "\cloudlabs-common\cloudlabs-windows-functions.ps1"
. $commonscriptpath

# Run Imported functions from cloudlabs-windows-functions.ps1

#CloudLabsManualAgent

CloudLabsManualAgent Install

WindowsServerCommon
InstallCloudLabsShadow $ODLID $InstallCloudLabsShadow
InstallAzPowerShellModule


Function Enable-CloudLabsEmbeddedShadow($vmAdminUsername, $trainerUserName, $trainerUserPassword)
{
Write-Host "Enabling CloudLabsEmbeddedShadow"
#Created Trainer Account and Add to Administrators Group
$trainerUserPass = $trainerUserPassword | ConvertTo-SecureString -AsPlainText -Force

New-LocalUser -Name $trainerUserName -Password $trainerUserPass -FullName "$trainerUserName" -Description "CloudLabs EmbeddedShadow User" -PasswordNeverExpires
Add-LocalGroupMember -Group "Administrators" -Member "$trainerUserName"

#Add Windows regitary to enable Shadow
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v Shadow /t REG_DWORD /d 2

#Download Shadow.ps1 and Shadow.xml file in VM
$drivepath="C:\Users\Public\Documents"
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/Shadow.ps1","$drivepath\Shadow.ps1")
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/shadow.xml","$drivepath\shadow.xml")
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/ShadowSession.zip","C:\Packages\ShadowSession.zip")
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/executetaskscheduler.ps1","$drivepath\executetaskscheduler.ps1")
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/shadowshortcut.ps1","$drivepath\shadowshortcut.ps1")

# Unzip Shadow User Session Shortcut to Trainer Desktop
#$trainerloginuser= "$trainerUserName" + "." + "$($env:ComputerName)"
#Expand-Archive -LiteralPath 'C:\Packages\ShadowSession.zip' -DestinationPath "C:\Users\$trainerloginuser\Desktop" -Force
#Expand-Archive -LiteralPath 'C:\Packages\ShadowSession.zip' -DestinationPath "C:\Users\$trainerUserName\Desktop" -Force

#Replace vmAdminUsernameValue with VM Admin UserName in script content 
(Get-Content -Path "$drivepath\Shadow.ps1") | ForEach-Object {$_ -Replace "vmAdminUsernameValue", "$vmAdminUsername"} | Set-Content -Path "$drivepath\Shadow.ps1"
(Get-Content -Path "$drivepath\shadow.xml") | ForEach-Object {$_ -Replace "vmAdminUsernameValue", "$trainerUserName"} | Set-Content -Path "$drivepath\shadow.xml"
(Get-Content -Path "$drivepath\shadow.xml") | ForEach-Object {$_ -Replace "ComputerNameValue", "$($env:ComputerName)"} | Set-Content -Path "$drivepath\shadow.xml"
(Get-Content -Path "$drivepath\shadowshortcut.ps1") | ForEach-Object {$_ -Replace "vmAdminUsernameValue", "$trainerUserName"} | Set-Content -Path "$drivepath\shadowshortcut.ps1"
sleep 2

# Scheduled Task to Run Shadow.ps1 AtLogOn
schtasks.exe /Create /XML $drivepath\shadow.xml /tn Shadowtask

$Trigger= New-ScheduledTaskTrigger -AtLogOn
$User= "$($env:ComputerName)\$trainerUserName" 
$Action= New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File $drivepath\shadowshortcut.ps1 -WindowStyle Hidden"
Register-ScheduledTask -TaskName "shadowshortcut" -Trigger $Trigger -User $User -Action $Action -RunLevel Highest -Force
}


# To resolve the error of https://github.com/microsoft/MCW-App-modernization/issues/68. The cause of the error is Powershell by default uses TLS 1.0 to connect to website, but website security requires TLS 1.2. You can change this behavior with running any of the below command to use all protocols. You can also specify single protocol.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Ssl3
[Net.ServicePointManager]::SecurityProtocol = "Tls, Tls11, Tls12, Ssl3"

Install-WindowsFeature -name Web-Server -IncludeManagementTools

$branchName = "prod-1"

# Enable Embedded shadow
Enable-CloudLabsEmbeddedShadow $vmAdminUsername $trainerUserName $trainerUserPassword

# Download and extract the starter solution files
# ZIP File sometimes gets corrupted
Write-Host "Downloading MCW-App-modernization from GitHub" -ForegroundColor Green
New-Item -ItemType directory -Path C:\MCW
while((Get-ChildItem -Directory C:\MCW | Measure-Object).Count -eq 0 )
{
    (New-Object System.Net.WebClient).DownloadFile("https://github.com/CloudLabs-MCW/MCW-App-modernization/zipball/$branchName", 'C:\MCW.zip')
    Expand-Archive -LiteralPath 'C:\MCW.zip' -DestinationPath 'C:\MCW' -Force
}


#rename the random branch name
$item = get-item "c:\mcw\*"
Rename-Item $item -NewName "MCW-App-modernization-$branchName"


# Copy Web Site Files
Expand-Archive -LiteralPath "C:\MCW\MCW-App-modernization-$branchName\Hands-on lab\lab-files\web-site-publish.zip" -DestinationPath 'C:\inetpub\wwwroot' -Force

# Replace SQL Connection String
((Get-Content -path C:\inetpub\wwwroot\config.release.json -Raw) -replace 'SETCONNECTIONSTRING',"Server=$SqlIP;Database=PartsUnlimited;User Id=PUWebSite;Password=$SqlPass;") | Set-Content -Path C:\inetpub\wwwroot\config.json

#Replace Path

(Get-Content C:\MCW\MCW-App-modernization-$branchName\'Hands-on lab'\lab-files\ARM-template\webvm-logon-install.ps1) -replace "replacepath","$Path" | Set-Content C:\MCW\MCW-App-modernization-$branchName\'Hands-on lab'\lab-files\ARM-template\webvm-logon-install.ps1 -Verbos

# Downloading Deferred Installs
# Download App Service Migration Assistant 
(New-Object System.Net.WebClient).DownloadFile('https://appmigration.microsoft.com/api/download/windows/AppServiceMigrationAssistant.msi', 'C:\AppServiceMigrationAssistant.msi')
# Download Edge 
(New-Object System.Net.WebClient).DownloadFile('https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/e2d06b69-9e44-45e1-bdf5-b3b827fe06b2/MicrosoftEdgeEnterpriseX64.msi', 'C:\MicrosoftEdgeEnterpriseX64.msi')
# Download 3.1.4 SDK
(New-Object System.Net.WebClient).DownloadFile('https://download.visualstudio.microsoft.com/download/pr/70062b11-491c-403c-91db-9d84462ee292/5db435e39128cbb608e76bf5111ab3dc/dotnet-sdk-3.1.413-win-x64.exe', 'C:\dotnet-sdk-3.1.413-win-x64.exe')

# Schedule Installs for first Logon
$argument = "-File `"C:\MCW\MCW-App-modernization-$branchName\Hands-on lab\lab-files\ARM-template\webvm-logon-install.ps1`""
$triggerAt = New-ScheduledTaskTrigger -AtLogOn -User demouser
$action = New-ScheduledTaskAction -Execute "powershell" -Argument $argument 
Register-ScheduledTask -TaskName "Install Lab Requirements" -Trigger $triggerAt -Action $action -User demouser

# Download Windows Hosting
Wait-Install
(New-Object System.Net.WebClient).DownloadFile('https://download.visualstudio.microsoft.com/download/pr/a0da9621-68f0-439a-b617-4697ee0669e3/38eb4aa6e879b9f06b73599ea2e1535f/dotnet-hosting-5.0.10-win.exe', 'C:\dotnet-hosting-5.0.10-win.exe')
$pathArgs = {C:\dotnet-hosting-5.0.10-win.exe /Install /Quiet /Norestart /Logs logHostingPackage.txt}
Invoke-Command -ScriptBlock $pathArgs


# Install Git
Wait-Install
(New-Object System.Net.WebClient).DownloadFile('https://github.com/git-for-windows/git/releases/download/v2.30.0.windows.2/Git-2.30.0.2-64-bit.exe', 'C:\Git-2.30.0.2-64-bit.exe')
Start-Process -file 'C:\Git-2.30.0.2-64-bit.exe' -arg '/VERYSILENT /SUPPRESSMSGBOXES /LOG="C:\git_install.txt" /NORESTART /CLOSEAPPLICATIONS' -passthru | wait-process

# Install VS Code
Wait-Install
(New-Object System.Net.WebClient).DownloadFile('https://go.microsoft.com/fwlink/?LinkID=623230', 'C:\vscode.exe')
Start-Process -file 'C:\vscode.exe' -arg '/VERYSILENT /SUPPRESSMSGBOXES /LOG="C:\vscode_install.txt" /NORESTART /FORCECLOSEAPPLICATIONS /mergetasks="!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath"' -passthru | wait-process

# Download and install SQL Server Management Studio
Wait-Install
(New-Object System.Net.WebClient).DownloadFile('https://aka.ms/ssmsfullsetup', 'C:\SSMS-Setup.exe')
$pathArgs = {C:\SSMS-Setup.exe /Install /Quiet /Norestart /Logs logSSMS.txt}
Invoke-Command -ScriptBlock $pathArgs

#Cred file
CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $DeploymentID
    
#Replace sub and tenant id

#(Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "GET-SUBSCRIPTION-ID", "$azsubscriptionid"} | Set-Content -Path "c:\LabFiles\AzureCreds.txt"
#(Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "GET-TENANT-ID", "$aztenantid"} | Set-Content -Path "c:\LabFiles\AzureCreds.txt"


#Autologin
$Username = "demouser"
$Pass = "Password.1!!"
$RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty $RegistryPath 'AutoAdminLogon' -Value "1" -Type String 
Set-ItemProperty $RegistryPath 'DefaultUsername' -Value "$Username" -type String 
Set-ItemProperty $RegistryPath 'DefaultPassword' -Value "$Pass" -type String

$Validstatus="Pending"  ##Failed or Successful at the last step
$Validmessage="Post Deployment is Pending"

#Set the final deployment status
CloudlabsManualAgent setStatus

Stop-Transcript  

Restart-Computer
