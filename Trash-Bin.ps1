<#
.SYNOPSIS
A simple CLI tool to interact with the Windows Recycle Bin and delete files and folders.

.DESCRIPTION
- Supports deleting files/folders ( move items to recycle bin ).
- List recycle bin contents.
- Delete items from recycle bin.
- Restore items from recycle bin.

.PARAMETER Path
The file or folder to move to the recycle bin.

.PARAMETER Action
Use one of - list, l, purge, p, trash (default), t, restore, r.

.EXAMPLE
trash temp.txt				# Trashes temp.txt
trash list				# Trashes item named "list"
trash -Action trash -Path binod		# Trashes item named "binod"
trash -Action list			# Lists recycle bin contents
trash -Action purge -Path temp.txt	# Empty the specied file from recycle bin
trash -Action restore -Path binod	# Restore item named "binod" from recycle bin
#>
Function Start-TrashBinCLI {
	param(
		[Parameter(Position = 0, Mandatory = $false)]
		[System.String]$Path,

		[Parameter(Mandatory = $false)]
		[ValidateSet("trash", "t", "list", "l", "purge", "p", "restore", "r")]
		[System.String]$Action
	)
 
	# List the content of recycle bin
	Function List-RecycleBinContent {
		$Items = $($(New-Object -ComObject Shell.Application).Namespace(0xA)).Items()
        	$Folders = @()
        	$Files = @()
	        foreach ($Item in $Items) {
	        	if ($Item.IsFolder) {
	        		$Folders += $Item
	        	} else {
				$Files += $Item
	         	}
	        }

		if ($Folders -or $Files) {
			Write-Host ""
			# NOTE: For color to show you must be using PS7+ and a terminal supporting ANSI color codelike Windows Terminal.
			foreach ($Folder in $Folders) { Write-Host "`e[44;97m$($Folder.Name)`e[0m"}
			Write-Host ""
	        	foreach ($File in $Files) { Write-Host $File.Name }
			Write-Host ""
		} else {
			Write-Host "Recycle Bin is empty!" -ForegroundColor Yellow
		}


	}
	
	# TODO: Cannot move multipe items at once for now or use wild card like '*' - solve this
	# Move item into recycle bin
	Function Move-ToRecycleBin {
		Add-Type -AssemblyName Microsoft.VisualBasic
		$Item = Get-Item -Path $Path -ErrorAction SilentlyContinue
		if ($Item -eq $null) {
			Write-Host ("'{0}' Not Found!" -f $Path) -ForegroundColor Red
		} else {
			$FullPath=$Item.FullName
			Write-Verbose ("Moving '{0}' to the Recycle Bin" -f $FullPath)
			Write-Host ("Moving '{0}' to the Recycle Bin" -f $Path) -ForegroundColor Green
			
			# Main Logic
			if (Test-Path -Path $FullPath -PathType Container) {
        			[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($FullPath,'OnlyErrorDialogs','SendToRecycleBin')
			} else {
				[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($FullPath,'OnlyErrorDialogs','SendToRecycleBin')
			}
		}
	}
	
	# Remove item from recycle bin
	Function Remove-FromRecycleBin {

		if (!$Path) { Write-Host "Missing path!" -ForegroundColor Red; return }
		
		$Shell = New-Object -ComObject Shell.Application
		$RecycleBin = $Shell.NameSpace(0xa)
		# TODO: Enhance: Use Clear-RecycleBin cmdlet to empty recycle bin

		foreach ($Item in $RecycleBin.Items()) {
			if ($Item.Name -eq $Path) {
				Remove-Item -Path $Item.Path -Confirm:$false -Force -Recurse
				Write-Host "Item `"$Path`" removed from Recycle Bin" -ForegroundColor Green
				return
			}
		}

		Write-Host "Item `"$Path`" not found in Recycle Bin" -ForegroundColor Red
	}
	
	# Restore items from recycle bin
	Function Restore-FromRecycleBin {

		if (!$Path) { Write-Host "Missing path!" -ForegroundColor Red; return }

		$Shell = New-Object -ComObject Shell.Application
		# Decimal representation of (0xa) 
		$RecycleBin = $Shell.NameSpace(10)
		$OriginalLocationColumnNumber = & {
			try {
				for ($i=0; $i -lt 20; $i++) {
					#$ColumnName = $RecycleBin.GetDetailsOf($RecycleBin.Items().Item(0), $i)
					$ColumnName = $RecycleBin.GetDetailsOf($RecycleBin.Items(), $i)
					if ($ColumnName -eq "Original Location") { return $i }
				}
			} catch {
				#Write-Output "$_.error"
				Write-Error "Error with finding orginal location column number!"
				
			}
		}

		# FIX: Not able to restore if the original path doesn't exist or is moved or renamed
		foreach ($Item in $RecycleBin.Items()){
			if ($Item.Name -eq $Path) {
				$OriginalLocation = $RecycleBin.GetDetailsOf($Item, $OriginalLocationColumnNumber)
				
				if ($OriginalLocation) {
					try {
						$Shell.NameSpace($OriginalLocation).MoveHere($Item.Path)
					} catch {
						# TODO: If path is altered thencreate an new path just to restore the item.
						Write-Error "Original path may have been altered!: $_"
						return
					}
					Write-Host "Restored `"$Path`" to `"$OriginalLocation`"" -ForegroundColor Green
				} else {
					Write-Host "Could not determine original location for `"$Path`"" -Foreground Red
				}
				return
			}
		}

		Write-Host "Item `"$Path`" not found in Recycle Bin" -ForegroundColor Red
	}

	# Action Selection
	if ($Action) {
		switch ($Action.ToLower()) {
			{$_ -eq "trash" -or $_ -eq "t"} {
				if (!$Path) {
					Write-Host "Missing path!" -ForegroundColor Red
					return
				} else {
					Move-ToRecycleBin
					return
				}
			}

			{$_ -eq "list" -or $_ -eq "l"} {
				List-RecycleBinContent
				return
			}

			{$_ -eq "purge" -or $_ -eq "p"} {
				Remove-FromRecycleBin
				return
			}

			{$_ -eq "restore" -or $_ -eq "r"} {
				Restore-FromRecycleBin
				return
			}
		}
	}

	
	if($Path) {
		Move-ToRecycleBin
	}
	else {
		Write-Host "No action or path provided!" -ForegroundColor Yellow
	}
}

Set-Alias trash Start-TrashBinCLI
# TODO: Why folder doesn't delete / move to recycle bin if the item location is like "C:\Users\username\OneDrive\[ 8 ] Folder Space\Folder" edit1: it's because of "[" special char
#!REF: https://stackoverflow.com/questions/502002/how-do-i-move-a-file-to-the-recycle-bin-using-powershell

