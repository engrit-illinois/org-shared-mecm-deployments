# This is some miscellaneous code I developed to try to further troubleshoot strange issues with MECM clients which cause them (Software Center) to hang on various deployments.
# This is an issue that can be caused by several distinct underlying issues, some of which are already addressed here:
# - 
# - 

# This code didn't result in any fixes or revelations, but I wanted to save it for future reference.

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------
# The following code attempts to look at the data stored in the actual SQLCE database stored in ccmstore.sdf, which may or may not be equivalent to WMI-based data I've already explored previously.
# --------------------------------------------------------------------------------------------------------------------------------------------------------------------



#https://audministrator.wordpress.com/2014/07/01/powershell-accessing-ms-sql-compact-edition/
# Only works in PS 5.1
# Requires CcmExec service on remote host to be stopped (could be scripted here, but isn't currently)

function log($msg) {
	Write-Host $msg
}

log "Loading SQLCE DLL..."
$binPath = "C:\Program Files (x86)\Microsoft SQL Server Compact Edition\v4.0\Desktop\System.Data.SqlServerCe.dll";
[Reflection.Assembly]::LoadFile($binPath)

log "Creating connection string..."
$sdfPath = "\\engrit-mms-tvm0\c$\windows\ccm\ccmstore.sdf"
$connString = "Data Source=$sdfPath"
$conn = New-Object "System.Data.SqlServerCe.SqlCeConnection" $connString
 
log "Defining SQL command to get ConfigurationItems table..."
$cmdCi = New-Object "System.Data.SqlServerCe.SqlCeCommand"
$cmdCi.CommandType = [System.Data.CommandType]"Text"
$cmdCi.CommandText = "SELECT * FROM ConfigurationItems"
$cmdCi.Connection = $conn

log "Defining SQL command to get ConfigurationItemsState table..."
$cmdCiState = New-Object "System.Data.SqlServerCe.SqlCeCommand"
$cmdCiState.CommandType = [System.Data.CommandType]"Text"
$cmdCiState.CommandText = "SELECT * FROM ConfigurationItemState"
$cmdCiState.Connection = $conn

log "Getting data..."
$dataCi = New-Object "System.Data.DataTable"
$dataCiState = New-Object "System.Data.DataTable"
$conn.Open()
$dataCi.Load($cmdCi.ExecuteReader())
$dataCiState.Load($cmdCiState.ExecuteReader())
$conn.Close()

log "Merging data..."
# These are the only properties that look like they have any potentially valueable information,
# based on looking through the data from an endpoint
$relevantProps = @(
	"DisplayName",
	"Revision",
	"LatestRevision",
	"Applicability",
	"State",
	"DesiredState",
	"EvaluationState",
	"EnforcementState",
	"DCMDetectionState",
	"PersistOnWriteFilterDevices",
	"NotifyUser",
	"UserUIExperience",
	"ContentSize",
	"SuppressionState"
)

$data = $dataCi | ForEach-Object {
	$ciState = $_
	
	$model = ($_.ModelName).Replace("/RequiredApplication_","/Application_")
	$app = $dataCiState | Where { $_.ModelName -eq $model }
	$addData = [PSCustomObject]@{}
	if($app) {
		# Get values
		$relevantProperties | ForEach-Object {
			$prop = $_
			$newProp = "App-$prop"
			# These could be either strings, or arrays, depending on the number of matching apps
			# If array, then combine values into a single string
			$value = $app.$prop
			$joinedValue = @($value) -join ","
			$addData | Add-Member -NotePropertyName $newProp -NotePropertyValue $joinedValue
		}
	}
	else {
		# Use default "Not found" data
		$relevantProperties | ForEach-Object {
			$prop = $_
			$newProp = "App-$prop"
			$value = "Not found"
			$addData | Add-Member -NotePropertyName $newProp -NotePropertyValue $value
		}
	}
	
	$relevantProperties | ForEach-Object {
		$prop = $_
		$newProp = "App-$prop"
		$value = $addData.$newProp
		$ciState | Add-Member -NotePropertyName $newProp -NotePropertyValue $value -Force
	}
	
	$ciState
}

log "Organizing data..."
$relevantPropsNew = $relevantProperties | ForEach-Object {
	$prop = $_
	"App-$prop"
}
$order = @("CiId","ModelName","Revision","Type") + @($relevantPropsNew)
$data = $data | Select $order | Sort ModelName,Revision

# Don't really care about the Windows version requirement things
$data = $data | Where { $_.ModelName -notlike "Windows/*" }

log "Dumping data..."
$data | Select $order | Out-GridView



# --------------------------------------------------------------------------------------------------------------------------------------------------------------------
# End of above code
# --------------------------------------------------------------------------------------------------------------------------------------------------------------------



# --------------------------------------------------------------------------------------------------------------------------------------------------------------------
# The following code attempts to delete the ccmstore.sdf file and allow it to be regenerated, in the hopes that that will fix potential corruption issues in that database.
# --------------------------------------------------------------------------------------------------------------------------------------------------------------------



$ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$log = "c:\engrit\logs\delete-ccmstore.sdf_$($ts).log"

function log($msg) {
	$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$msg = "[$ts] $msg"
	Write-Host $msg
	$msg | Out-File $log -Append
}

function Log-FileInfo($num) {
	$info = Get-Item -Path $file
	$test = "Test: `"$num`""
	$size = "Size: `"$($info.Length / 1MB) MB`""
	# Creation time will likely not change due to filesystem tunneling
	# https://devblogs.microsoft.com/oldnewthing/20050715-14/?p=34923
	$created = "Created: `"$($info.CreationTime)`""
	$modified = "Modified: `"$($info.LastWriteTime)`""
	$accessed = "Accessed: `"$($info.LastAccessTime)`""
	log "    $test, $size, $created, $modified, $accessed"
}

$file = "$($env:windir)\ccm\ccmstore.sdf"
log "File: `"$file`""

log "Logging current file info..."
Log-FileInfo 1

log "Stopping CcmExec service..."
$result = Stop-Service -Name "CcmExec" -Force *>&1 | Out-String
log "    $result"

log "Deleting file..."
$result = Remove-Item $file -Force *>&1 | Out-String
log "    $result"

log "Starting CcmExec service..."
$result = Start-Service -Name "CcmExec" *>&1 | Out-String
log "    $result"

log "Waiting for file to be regenerated..."
$intervalSecs = 5
$elapsedSecs = 0
while(-not (Test-Path -Path $file -PathType "Leaf")) {
	log "    File not found. Waiting `"$intervalSecs`" seconds..."
	Start-Sleep -Seconds $intervalSecs
	$elapsedSecs += $intervalSecs
	log "    Waited `"$elapsedSecs`" seconds."
}
log "File found."

log "Logging new file info..."
Log-FileInfo 2

log "EOF"



# --------------------------------------------------------------------------------------------------------------------------------------------------------------------
# End of above code
# --------------------------------------------------------------------------------------------------------------------------------------------------------------------
