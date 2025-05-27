Add-Type -AssemblyName Microsoft.VisualBasic
Function Send-ToRecycleBin {
	param([System.String]$path)
 
	# List the content of Recycle-Bin
	$RecycleList = {
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
	        foreach ($folder in $folders) { Write-Host $folder.Name -ForegroundColor Blue }
	        foreach ($file in $files) { Write-Host $file.Name }
	}
 
	if ($path -eq "") {
		Write-Host "No File/Folder Given" -ForegroundColor Red
		return
	}
	elseif ($path -eq "//list") {
		& $RecycleList
		return
	}

	$item = Get-Item -Path $path -ErrorAction SilentlyContinue
	if ($item -eq $null) {
    		Write-Host ("'{0}' Not Found!" -f $path) -ForegroundColor Red
	} else {
        	$fullpath=$item.FullName
        	Write-Verbose ("Moving '{0}' to the Recycle Bin" -f $fullpath)
        	#Write-Host ("Moving '{0}' to the Recycle Bin" -f $fullpath) -ForegroundColor Green 
        	Write-Host ("Moving '{0}' to the Recycle Bin" -f $path) -ForegroundColor Green 

  		# Main Logic
        	if (Test-Path -Path $fullpath -PathType Container) {
        		[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($fullpath,'OnlyErrorDialogs','SendToRecycleBin')
        	} else {
            		[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($fullpath,'OnlyErrorDialogs','SendToRecycleBin')
        	}
	}
}
Set-Alias trash Send-ToRecycleBin
# TODO: Why folder doesn't delete / move to recycle bin if the item location is like "C:\Users\username\OneDrive\[ 8 ] Folder Space\Folder" edit1: it's because of "[" special char
#!REF: https://stackoverflow.com/questions/502002/how-do-i-move-a-file-to-the-recycle-bin-using-powershell
