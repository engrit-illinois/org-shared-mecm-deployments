# Script and script documentation home: https://github.com/engrit-illinois/org-shared-mecm-deployments
# Org shared deployment model documentation home: https://wiki.illinois.edu/wiki/display/engritprivate/SCCM+-+Org+shared+collections+and+deployments
# By mseng3

function Report-UnnecessaryDirectDeployments {

	param(
		[string]$OutputPath="c:\engrit\logs",
	
		[string]$SiteCode="MP0",
		
		[string]$Provider="sccmcas.ad.uillinois.edu",
		
		[string]$CMPSModulePath="$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
	)
	
	$ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
	$OUTPUT_FILENAME_BASE = "Report-UnnecessaryDirectDeployments_$ts"
	$LOG = "$OutputPath\$($OUTPUT_FILENAME_BASE).log"
	$CSV = "$OutputPath\$($OUTPUT_FILENAME_BASE).csv"
	
	function log($msg) {
		if(!(Test-Path -PathType leaf -Path $LOG)) {
			$shutup = New-Item -ItemType File -Force -Path $LOG
		}
		$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss:ffff"
		Write-Host "[$ts] $msg"
		$msg | Out-File $LOG -Append
	}

	function Prep-MECM {
		log "Preparing connection to MECM..."
		$initParams = @{}
		if((Get-Module ConfigurationManager) -eq $null) {
			# The ConfigurationManager Powershell module switched filepaths at some point around CB 18##
			# So you may need to modify this to match your local environment
			Import-Module $CMPSModulePath @initParams -Scope Global
		}
		if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
			New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $Provider @initParams
		}
		Set-Location "$($SiteCode):\" @initParams
		log "Done prepping connection to MECM."
	}
	
	function Get-DupeDeps {
		# Get list of org shared software deployment collections
		log "Getting all collections..."
		$collsAll = Get-CMDeviceCollection
		log "Found $(@($collsAll).count) collections."
		
		log "Filtering to org shared software deployment collections (`"UIUC-ENGR-Deploy *`")..."
		$collsShared = $collsAll | Where { $_.Name -like "UIUC-ENGR-Deploy *" } | Sort Name
		log "Found $(@($collsShared).count) shared collections."
			
		# Get list of application deployments to these collections
		# Count required and available deployments separately
		log "Getting deployments to shared collections..."
		$dupeDeps = @()
		$i = 0
		foreach($coll in $collsShared) {
			$i += 1
			log "    Getting deployments to collection #$i/$(@($collsShared).count): `"$($coll.Name)`"..."
			$depsThisColl = Get-CMApplicationDeployment -CollectionName $coll.Name
			log "        Found $(@($depsThisColl).count) deployments to this shared collection."
			if(@($depsThisColl).count -ne 1) {
				log "        Warning: there should be exactly 1 deployment to shared collections!"
			}
			
			# For each deployment/purpose combination
			log "        Getting collections where this app deployment/purpose combination is duplicated..."
			foreach($dep in $depsThisColl) {
				# https://www.petervanderwoude.nl/post/tag/applications/
				# https://docs.microsoft.com/en-us/mem/configmgr/develop/reference/apps/sms_applicationassignment-server-wmi-class
				# 0 = Required, 2 = Available
				$purposes = @{
					0 = "Required"
					2 = "Available"
				}
				$purpose = $purposes.($dep.OfferTypeID)
				
				# https://stackoverflow.com/questions/14748402/uninstalling-applications-using-sccm-sdk
				# https://docs.microsoft.com/en-us/mem/configmgr/develop/reference/compliance/sms_ciassignmentbaseclass-server-wmi-class
				# https://www.reddit.com/r/SCCM/comments/80fczg/help_does_anyone_know_where_action_is_derived/
				# 1 = Install (a.k.a. Required), 2 = Uninstall (a.k.a.  Not Allowed)
				$actions = @{
					1 = "Install"
					2 = "Uninstall"
				}
				$action = $actions.($dep.DesiredConfigType)
				
				log "            App: $($dep.ApplicationName)"
				log "            Purpose: $purpose"
				log "            Action: $action"
				
				# Get all deployments of the app of this deployment
				log "            Getting all deployments of app..."
				$depsThisApp = Get-CMApplicationDeployment -Name $dep.ApplicationName
				log "                Found $(@($depsThisApp).count) deployments of app."
				
				# Filter out the deployment to this shared collection
				$otherDepsThisApp = $depsThisApp | Where { $_.CollectionName -ne $dep.CollectionName }
				
				# Filter out deployments with a different purpose than this shared collection
				log "            Getting all deployments (to other collections) which have the same action and purpose..."
				$dupeDepsThisApp = $otherDepsThisApp | Where { $_.OfferTypeID -eq $dep.OfferTypeID }
				$dupeDepsThisApp = $dupeDepsThisApp | Where { $_.DesiredConfigType -eq $dep.DesiredConfigType }
				log "                Found $(@($dupeDepsThisApp).count) other collections with duplicate app deployment, action and purpose."
				
				$dupeDepsThisApp | ForEach {
					$_ | Add-Member -NotePropertyName "Action" -NotePropertyValue $action
					$_ | Add-Member -NotePropertyName "Purpose" -NotePropertyValue $purpose
					$_ | Add-Member -NotePropertyName "Org Deployment Collection" -NotePropertyValue $dep.CollectionName
					$_ | Add-Member -NotePropertyName "Org Deployment Supersedence Enabled" -NotePropertyValue $dep.UpdateSupersedence
				}
				
				$dupeDeps += @($dupeDepsThisApp)
			}
		}
		
		log "Found $(@($dupeDeps).count) total deployments to other collections that duplicate those to shared collections."
		
		$dupeDeps
	}
	
	function Export-DupeDeps($dupeDeps) {
		log "Exporting data to `"$CSV`"..."
		
		# Format list
		$columns = @(
			@{ Name="Redundant Deployment Collection"; Expression={$_.CollectionName} }
			@{ Name="Redundant Deployment Supersedence Enabled"; Expression={$_.UpdateSupersedence} }
			"Org Deployment Collection"
			"Org Deployment Supersedence Enabled"
			@{ Name="Application Name"; Expression={$_.ApplicationName} }
			"Action"
			"Purpose"
		)
		$dupeDeps = $dupeDeps | Select $columns
		
		# Export list
		$dupeDeps | Export-Csv -Path $CSV -NoTypeInformation -Encoding Ascii
	}
	
	function Do-Stuff {
		$myPWD = $pwd.path
		Prep-MECM
		
		$dupeDeps = Get-DupeDeps
		Export-DupeDeps $dupeDeps
		
		Set-Location $myPWD
	}
	
	Do-Stuff
	
	log "EOF"
}