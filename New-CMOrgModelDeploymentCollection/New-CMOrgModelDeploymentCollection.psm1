# Script and script documentation home: https://github.com/engrit-illinois/org-shared-mecm-deployments
# Org shared deployment model documentation home: https://wiki.illinois.edu/wiki/display/engritprivate/SCCM+-+Org+shared+collections+and+deployments
# By mseng3

function New-CMOrgModelDeploymentCollection {

	param(
		[Parameter(Position=0,Mandatory=$true)]
		[string]$App,
		
		[switch]$ISOnly,
		
		[switch]$SkipAvailable,
		
		[switch]$SkipRequired,
		
		[switch]$Uninstall,
		
		# Prefix that all unit's apps and collections have
		# This is probably unique to the UofI environment
		# Script assumes this is consistent
		# i.e. "UIUC-ENGR-" assumes all collections and apps have exactly this prefix, and none have a prefix of e.g. "ENGR-UIUC"
		[string]$Prefix="UIUC-ENGR-",
		
		[int]$DeploymentDelaySec=10,
		
		[string]$SiteCode="MP0",
		
		[string]$Provider="sccmcas.ad.uillinois.edu",
		
		[string]$CMPSModulePath="$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
	)
	
	function log($msg) {
		$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss:ffff"
		Write-Host "[$ts] $msg"
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
	
	function App-Exists {
		log "Checking that specified application exists..."
		$appResult = Get-CMApplication -Fast -Name $App
		if($appResult) {
			log "    Result returned."
			if($appResult.LocalizedDisplayName -eq $App) {
				log "    Looks good."
				$exists = $true
			}
			else {
				log "    Result does not contain expected data!"
				log ($result | Out-String)
			}
		}
		else {
			log "No result was returned! Are you sure this app exists, and is an app (as opposed to a package)?"
		}
		$exists
	}
		
	function New-Coll($type, $collNameBase, $limitingColl, $sched) {
		# Make new collection
		
		if($type -eq "Available") {
			$action = "Install"
			$purpose = "Available"
		}
		elseif($type -eq "Required") {
			$action = "Install"
			$purpose = "Required"
		}
		elseif($type -eq "Uninstall") {
			$action = "Uninstall"
			$purpose = "Required"
		}
		else {
			throw "Incorrect type sent to New-Coll function!"
		}
		
		$coll = "$collNameBase ($purpose)"
		log "Creating new `"$purpose`" collection: `"$coll`"..."
		$collResult = New-CMDeviceCollection -Name $coll -LimitingCollectionName $limitingColl -RefreshType "Periodic" -RefreshSchedule $sched
		
		if($collResult) {
			log "    Result returned"
			if($collResult.Name -eq $coll) {
				log "    Looks successful."
			}
			else {
				log "    Result does not contain expected data!"
				log ($collResult | Out-String)
			}
		}
		else {
			log "    No result was returned! Something went wrong :/"
		}
		
		log ""
		
		# Wait to make sure collection is created before trying to deploy to it
		log "Waiting $DeploymentDelaySec seconds before deploying to new collection..."
		Start-Sleep -Seconds 10
		
		log ""
		
		# Make deployment to new collection
		log "Deploying app `"$appname`" as `"$purpose`" to collection `"$coll`"..."
		
		$depResult = New-CMApplicationDeployment -Name $App -CollectionName $coll -DeployAction $action -DeployPurpose $purpose -UpdateSupersedence $true
		
		if($depResult) {
			log "    Result returned"
			if($depResult.AssignmentName -eq "$($App)_$($coll)_$action") {
				log "    Looks successful."
			}
			else {
				log "    Result does not contain expected data!"
				log ($depResult | Out-String)
			}
		}
		else {
			log "    No result was returned! Something went wrong :/"
		}
	}
	
	function Get-AppName {
		$appName = $App.Replace($Prefix,"")
		$regex = "$($Prefix)-*"
		if($App -match $regex) {
			log "App has `"$Prefix`" prefix. Removing this and taking the core app name: `"$appName`"."
		}
		else {
			log "App does not have `"$Prefix`" prefix. Probably a campus app."
		}
		
		$appName
	}
	
	function Get-BaseCollName($appName) {
		$collNamePrefix = "$($Prefix)"
		if($ISOnly) {
			$collNamePrefix = "$($Prefix)IS "
		}
		
		$collNamePrefixAction = "$($collNamePrefix)Deploy"
		if($Uninstall) {
			$collNamePrefixAction = "$($collNamePrefix)Uninstall"
		}
		
		$collNameBase = "$collNamePrefixAction $appName"
		
		$collNameBase
	}
	
	function Get-LimitingColl {
		$limitingColl = "$($Prefix)All Systems"
		if($ISOnly) {
			$limitingColl = "$($Prefix)Instructional"
		}
		
		$limitingColl
	}
	
	# Builds schedule object to send to New-CMDeviceCollection
	# Hard coded to be 1am daily, as defined by the design decisions documented on the wiki
	function Get-Sched {
		$schedStartDate = Get-Date -Format "yyyy-MM-dd"
		$schedStartTime = "01:00"
		$sched = New-CMSchedule -Start "$schedStartDate $schedStartTime" -RecurInterval "Days" -RecurCount 1
		
		$sched
	}
	
	function Test-SupportedPowershellVersion {
		log "This custom module (and the overall ConfigurationManager Powershell module) only support Powershell v5.1. Checking Powershell version..."
		
		$ver = $Host.Version
		log "Powershell version is `"$($ver.Major).$($ver.Minor)`"."
		if(
			($ver.Major -eq 5) -and
			($ver.Minor -eq 1)
		) {
			return $true
		}
		return $false
	}
	
	function Do-Stuff {
		log ""
		
		# Check that supported Powershell version is being used
		if(Test-SupportedPowershellVersion) {
			
			$myPWD = $pwd.path
			Prep-MECM
			log ""
		
			# Check that the specified app exists
			$exists = App-Exists
			
			if($exists) {
			
				log ""
			
				# Get core app name
				$appName = Get-AppName
				
				log ""
				
				# Some logging
				if($ISOnly) {
					log "-ISOnly was specified."
				}
				else {
					log "-ISOnly was not specified."
				}
				
				# Build base name of new collection(s) and limiting collection name
				$collNameBase = Get-BaseCollName $appName
				log "    Collection name(s) will be `"$collNameBase (<purpose>)`"."
				
				$limitingColl = Get-LimitingColl
				log "    Limiting collection(s) will be `"$limitingColl`"."
				
				log ""
				
				# Build membership evaluation schedule
				$sched = Get-Sched
				
				# Logic for which collections/deployments to create
				if(!$Uninstall) {
					if(!$SkipAvailable) {
						New-Coll "Available" $collNameBase $limitingColl $sched
					}
					else {
						log "-SkipAvailable was specified. Skipping creation of `"Available`" collection/deployment."
					}
					
					log ""
					
					if(!$SkipRequired) {
						New-Coll "Required" $collNameBase $limitingColl $sched
					}
					else {
						log "-SkipRequired was specified. Skipping creation of `"Required`" collection/deployment."
					}
				}
				else {
					New-Coll "Uninstall" $collNameBase $limitingColl $sched
				}
			}
			
			log ""
			Set-Location $myPWD
		}
	}
	
	Do-Stuff
	log "EOF"
	log ""
}