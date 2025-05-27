# $FirstName = $args[0] 
# $LastName = $args[1] 
# Write-Output "First Name: $FirstName" 
# Write-Output "Last Name: $LastName"

# TODO: When trash command is invoked without any arg, it should give graceful msg or help ( help from help module )
# TODO: Know why folder doesn't delete / move to recycle bin if the item location is like "C:\Users\username\OneDrive\[ 8 ] Folder Space\Folder" edit1: it's because of "[" special char

Add-Type -AssemblyName Microsoft.VisualBasic
Function Send-ToRecycleBin($Path) {
	
	# What i noticed is script block should be at the top of the function, need to verify again!
	$RecycleList = {
		# Simplified Version Without Creating Variables
		$items = $($(New-Object -ComObject Shell.Application).Namespace(0xA)).Items()
        	$folders = @()
        	$files = @()
	
	        foreach ($item in $items) {
	        	if ($item.IsFolder) {
	        		$folders += $item
	        	} else {
				$files += $item
	        	}
	        }
	
	        foreach ($folder in $folders) {
	          	Write-Host $folder.Name -ForegroundColor Blue
	        }

	        foreach ($file in $files) {
        		Write-Host $file.Name
       		}
	}

	if ($path -eq $null -or $path -eq "hello") {
		Write-Host "No File/Folder Given" -ForegroundColor Red # maybe i can use Write-Error here edit1: nope!
		return
	}
	elseif ($path -eq "//list") {
		& $RecycleList
		return
	}

	

	$item = Get-Item -Path $Path -ErrorAction SilentlyContinue

	if ($item -eq $null) {
    		
		#Write-Error("'{0}' not found" -f $Path)

		# I would prefer using Write-Host
    		Write-Host ("'{0}' Not Found!" -f $Path) -ForegroundColor Red
	
	} else {

        	$fullpath=$item.FullName # TODO: What is this .FullName
		
		# If you whan to see what verbose output stream is logging uncomment the following code.
		#$VerbosePreference = "Continue" # Make it possible to view verbose output in CLI as the prefernence was SilentlyContinue by default
        	Write-Verbose ("Moving '{0}' to the Recycle Bin" -f $fullpath) # Try using "-Verbose" which displays any verbose messages, regardless of the value of the $VerbosePreference variable.
		#$VerbosePreference = "SilentlyContinue"
		
        	#Write-Host ("Moving '{0}' to the Recycle Bin" -f $fullpath) -ForegroundColor Green 
        	Write-Host ("Moving '{0}' to the Recycle Bin" -f $Path) -ForegroundColor Green 

		
		# Main Logic
        	if (Test-Path -Path $fullpath -PathType Container) {
        		[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($fullpath,'OnlyErrorDialogs','SendToRecycleBin')
        	} else {
            		[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($fullpath,'OnlyErrorDialogs','SendToRecycleBin')
        	}
	}
}
Set-Alias trash Send-ToRecycleBin # -Option AllScope


#!REF: https://stackoverflow.com/questions/502002/how-do-i-move-a-file-to-the-recycle-bin-using-powershell
