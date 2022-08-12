# Rules for creating PowerShell-based detection methods
See: https://www.danielengberg.com/detect-text-file-content-using-powershell-detection-method-sccm/
 
 | Script exit code | Data read from STDOUT | Data read from STDERR | Script result | Application detection state | 
 | 0 | Empty | Empty | Success | Not installed | 
 | 0 | Empty | Not empty | Failure | Unknown | 
 | 0 | Not empty | Empty | Success | Installed | 
 | 0 | Not empty | Not empty | Success | Installed | 
 | Non-zero value | Empty | Empty | Failure | Unknown | 
 | Non-zero value | Empty | Not empty | Failure | Unknown | 
 | Non-zero value | Not empty | Empty | Failure | Unknown | 
 | Non-zero value | Not empty | Not empty | Failure | Unknown | 
 
The most relevant lines here are:
 | Script exit code | Data read from STDOUT | Data read from STDERR | Script result | Application detection state | 
 | 0 | Empty | Empty | Success | Not installed | 
 | 0 | Not empty | Empty | Success | Installed | 
 | 0 | Not empty | Not empty | Success | Installed | 
 
Any other combinations will result in an unknown detection state.
