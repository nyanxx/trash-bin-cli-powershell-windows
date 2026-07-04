<#
.SYNOPSIS
A simple CLI tool to interact with the Windows Recycle Bin and delete files and folders.

.DESCRIPTION
- Supports deleting files/folders ( move items to recycle bin ), including multiple paths and wildcards.
- List recycle bin contents (name, size, date deleted, original location).
- Delete items from recycle bin, or empty the whole bin.
- Restore items from recycle bin, optionally to an alternate destination.

.PARAMETER Path
One or more files/folders to move to the recycle bin. Supports wildcards and arrays/pipeline input.
For -Action purge, pass "all" to empty the whole Recycle Bin.

.PARAMETER Action
Use one of - list, l, purge, p, trash (default), t, restore, r.

.PARAMETER Destination
Used with -Action restore. If the original location no longer exists, restore the item here instead.

.PARAMETER Force
Used with -Action purge -Path all. Skips the confirmation prompt when emptying the Recycle Bin.

.EXAMPLE
trash temp.txt					# Trashes temp.txt
trash list					# Trashes item named "list"
trash *.log					# Trashes all .log files in the current folder
trash a.txt, b.txt				# Trashes multiple items
trash -Action trash -Path binod		# Trashes item named "binod"
trash -Action list				# Lists recycle bin contents
trash -Action purge -Path temp.txt		# Removes the specified file from recycle bin
trash -Action purge -Path all -Force		# Empties the whole Recycle Bin without prompting
trash -Action restore -Path binod		# Restore item named "binod" from recycle bin
trash -Action restore -Path binod -Destination C:\Temp	 # Restore to an alternate location
#>
Function Start-TrashBinCLI {
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
	param(
		[Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
		[System.String[]]$Path,

		[Parameter(Mandatory = $false)]
		[ValidateSet("trash", "t", "list", "l", "purge", "p", "restore", "r")]
		[System.String]$Action,

		[Parameter(Mandatory = $false)]
		[System.String]$Destination,

		[Parameter(Mandatory = $false)]
		[switch]$Force
	)

	# Resolve a "Name" / "Original Location" / "Date Deleted" / "Size" column index dynamically (locale-safe)
	Function Get-RecycleBinColumnIndex {
		param($RecycleBin, [string]$ColumnName)
		for ($i = 0; $i -lt 30; $i++) {
			$Label = $RecycleBin.GetDetailsOf($RecycleBin.Items(), $i)
			if ($Label -eq $ColumnName) { return $i }
		}
		return -1
	}

	# List the content of recycle bin
	Function List-RecycleBinContent {
		$Shell = New-Object -ComObject Shell.Application
		$RecycleBin = $Shell.NameSpace(0xA)
		$Items = $RecycleBin.Items()

		if ($Items.Count -eq 0) {
			Write-Host "Recycle Bin is empty!" -ForegroundColor Yellow
			return
		}

		$SizeCol = Get-RecycleBinColumnIndex -RecycleBin $RecycleBin -ColumnName "Size"
		$DateCol = Get-RecycleBinColumnIndex -RecycleBin $RecycleBin -ColumnName "Date Deleted"
		$LocCol = Get-RecycleBinColumnIndex -RecycleBin $RecycleBin -ColumnName "Original Location"

		$Rows = foreach ($Item in $Items) {
			[PSCustomObject]@{
				Name             = $Item.Name
				IsFolder         = $Item.IsFolder
				Size             = if ($SizeCol -ge 0) { $RecycleBin.GetDetailsOf($Item, $SizeCol) } else { "" }
				"Date Deleted"   = if ($DateCol -ge 0) { $RecycleBin.GetDetailsOf($Item, $DateCol) } else { "" }
				"Original Location" = if ($LocCol -ge 0) { $RecycleBin.GetDetailsOf($Item, $LocCol) } else { "" }
			}
		}

		Write-Host ""
		# NOTE: For color to show you must be using PS7+ and a terminal supporting ANSI color codes like Windows Terminal.
		$Rows | Where-Object { $_.IsFolder } | ForEach-Object { Write-Host "`e[44;97m$($_.Name)`e[0m" }
		Write-Host ""
		$Rows | Select-Object Name, Size, "Date Deleted", "Original Location" | Format-Table -AutoSize
	}

	# Move item(s) into recycle bin - supports multiple paths, arrays, and wildcards
	Function Move-ToRecycleBin {
		Add-Type -AssemblyName Microsoft.VisualBasic

		$ResolvedItems = foreach ($SinglePath in $Path) {
			# "." means "empty this folder", not "trash this folder"
			if ($SinglePath -in @('.', './', '.\')) {
				$Children = Get-ChildItem -LiteralPath (Get-Location) -Force
				if (-not $Children) {
					Write-Host "Folder is already empty, nothing to trash" -ForegroundColor Yellow
					continue
				}
				$Children | Select-Object @{Name = 'Path'; Expression = { $_.FullName } }
				continue
			}

			$Found = Resolve-Path -Path $SinglePath -ErrorAction SilentlyContinue
			if (-not $Found) {
				Write-Host ("'{0}' Not Found!" -f $SinglePath) -ForegroundColor Red
				continue
			}
			$Found
		}

		foreach ($Resolved in $ResolvedItems) {
			$Item = Get-Item -LiteralPath $Resolved.Path -ErrorAction SilentlyContinue
			if ($null -eq $Item) {
				Write-Host ("'{0}' Not Found!" -f $Resolved.Path) -ForegroundColor Red
				continue
			}

			$FullPath = $Item.FullName
			if (-not $PSCmdlet.ShouldProcess($FullPath, "Move to Recycle Bin")) { continue }

			Write-Verbose ("Moving '{0}' to the Recycle Bin" -f $FullPath)
			Write-Host ("Moving '{0}' to the Recycle Bin" -f $FullPath) -ForegroundColor Green

			if (Test-Path -LiteralPath $FullPath -PathType Container) {
				[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($FullPath, 'OnlyErrorDialogs', 'SendToRecycleBin')
			} else {
				[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($FullPath, 'OnlyErrorDialogs', 'SendToRecycleBin')
			}
		}
	}

	# Remove item(s) from recycle bin, or empty the whole bin with -Path all
	Function Remove-FromRecycleBin {

		if (!$Path) { Write-Host "Missing path!" -ForegroundColor Red; return }

		if ($Path.Count -eq 1 -and $Path[0] -eq 'all') {
			if ($PSCmdlet.ShouldProcess("Recycle Bin", "Empty (permanently delete all items)")) {
				Clear-RecycleBin -Force:$Force -Confirm:$false
				Write-Host "Recycle Bin emptied" -ForegroundColor Green
			}
			return
		}

		$Shell = New-Object -ComObject Shell.Application
		$RecycleBin = $Shell.NameSpace(0xa)
		$LocCol = Get-RecycleBinColumnIndex -RecycleBin $RecycleBin -ColumnName "Original Location"

		foreach ($SinglePath in $Path) {
			$Found = @($RecycleBin.Items() | Where-Object { $_.Name -eq $SinglePath })

			if ($Found.Count -eq 0) {
				Write-Host "Item `"$SinglePath`" not found in Recycle Bin" -ForegroundColor Red
				continue
			}

			$Target = $Found[0]
			if ($Found.Count -gt 1) {
				Write-Host "Multiple items named `"$SinglePath`" found in Recycle Bin:" -ForegroundColor Yellow
				for ($i = 0; $i -lt $Found.Count; $i++) {
					$OrigLoc = if ($LocCol -ge 0) { $RecycleBin.GetDetailsOf($Found[$i], $LocCol) } else { "" }
					Write-Host "  [$i] $OrigLoc"
				}
				$Choice = Read-Host "Enter the number of the item to purge (or press Enter to cancel)"
				if ($Choice -notmatch '^\d+$' -or [int]$Choice -ge $Found.Count) {
					Write-Host "Cancelled." -ForegroundColor Yellow
					continue
				}
				$Target = $Found[[int]$Choice]
			}

			if ($PSCmdlet.ShouldProcess($SinglePath, "Permanently delete from Recycle Bin")) {
				Remove-Item -LiteralPath $Target.Path -Confirm:$false -Force -Recurse
				Write-Host "Item `"$SinglePath`" removed from Recycle Bin" -ForegroundColor Green
			}
		}
	}

	# Restore items from recycle bin, optionally to an alternate -Destination
	Function Restore-FromRecycleBin {

		if (!$Path) { Write-Host "Missing path!" -ForegroundColor Red; return }

		$Shell = New-Object -ComObject Shell.Application
		# Decimal representation of (0xa)
		$RecycleBin = $Shell.NameSpace(10)
		$LocCol = Get-RecycleBinColumnIndex -RecycleBin $RecycleBin -ColumnName "Original Location"

		foreach ($SinglePath in $Path) {
			$Found = @($RecycleBin.Items() | Where-Object { $_.Name -eq $SinglePath })

			if ($Found.Count -eq 0) {
				Write-Host "Item `"$SinglePath`" not found in Recycle Bin" -ForegroundColor Red
				continue
			}

			$Target = $Found[0]
			if ($Found.Count -gt 1) {
				Write-Host "Multiple items named `"$SinglePath`" found in Recycle Bin:" -ForegroundColor Yellow
				for ($i = 0; $i -lt $Found.Count; $i++) {
					$OrigLoc = if ($LocCol -ge 0) { $RecycleBin.GetDetailsOf($Found[$i], $LocCol) } else { "" }
					Write-Host "  [$i] $OrigLoc"
				}
				$Choice = Read-Host "Enter the number of the item to restore (or press Enter to cancel)"
				if ($Choice -notmatch '^\d+$' -or [int]$Choice -ge $Found.Count) {
					Write-Host "Cancelled." -ForegroundColor Yellow
					continue
				}
				$Target = $Found[[int]$Choice]
			}

			$OriginalLocation = if ($LocCol -ge 0) { $RecycleBin.GetDetailsOf($Target, $LocCol) } else { "" }
			$RestoreTo = $OriginalLocation

			if (-not $OriginalLocation -or -not (Test-Path -LiteralPath $OriginalLocation)) {
				if ($Destination) {
					$RestoreTo = $Destination
					Write-Host "Original location unavailable, restoring to `"$Destination`" instead" -ForegroundColor Yellow
				} else {
					Write-Host "Could not determine original location for `"$SinglePath`" (it may have been altered). Pass -Destination to restore elsewhere." -ForegroundColor Red
					continue
				}
			} elseif ($Destination) {
				$RestoreTo = $Destination
			}

			if (-not (Test-Path -LiteralPath $RestoreTo)) {
				New-Item -ItemType Directory -Path $RestoreTo -Force | Out-Null
			}

			if ($PSCmdlet.ShouldProcess($SinglePath, "Restore to `"$RestoreTo`"")) {
				try {
					$Before = @((Get-ChildItem -LiteralPath $RestoreTo -Force -ErrorAction SilentlyContinue).Name)
					$Shell.NameSpace($RestoreTo).MoveHere($Target.Path)

					# The Shell COM restore can drop the item under its internal Recycle Bin storage
					# name (e.g. $RKB6755) instead of its original name - detect and rename it back.
					$RestoredItem = Get-ChildItem -LiteralPath $RestoreTo -Force -ErrorAction SilentlyContinue |
						Where-Object { $_.Name -notin $Before } |
						Select-Object -First 1

					if ($RestoredItem -and $RestoredItem.Name -ne $Target.Name) {
						Rename-Item -LiteralPath $RestoredItem.FullName -NewName $Target.Name -Force
					}

					Write-Host "Restored `"$SinglePath`" to `"$RestoreTo`"" -ForegroundColor Green
				} catch {
					Write-Error "Failed to restore `"$SinglePath`": $_"
				}
			}
		}
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

	if ($Path) {
		Move-ToRecycleBin
	}
	else {
		Write-Host "No action or path provided!" -ForegroundColor Yellow
	}
}
Set-Alias trash Start-TrashBinCLI

# Tab completion for -Path: Recycle Bin item names when restoring/purging, filesystem paths otherwise
Register-ArgumentCompleter -CommandName Start-TrashBinCLI, trash -ParameterName Path -ScriptBlock {
	param($CommandName, $ParameterName, $WordToComplete, $CommandAst, $FakeBoundParameters)

	$RecycleBinActions = @('restore', 'r', 'purge', 'p')
	if ($FakeBoundParameters['Action'] -and $FakeBoundParameters['Action'].ToLower() -in $RecycleBinActions) {
		try {
			$Shell = New-Object -ComObject Shell.Application
			$RecycleBin = $Shell.NameSpace(0xA)
			$RecycleBin.Items() |
				Where-Object { $_.Name -like "$WordToComplete*" } |
				Select-Object -ExpandProperty Name -Unique |
				ForEach-Object { [System.Management.Automation.CompletionResult]::new("'$_'", $_, 'ParameterValue', $_) }
		} catch { }
		return
	}

	Get-ChildItem -Path "$WordToComplete*" -Force -ErrorAction SilentlyContinue |
		ForEach-Object {
			$Quoted = if ($_.Name -match '[\s'']') { "'$($_.Name)'" } else { $_.Name }
			[System.Management.Automation.CompletionResult]::new($Quoted, $_.Name, 'ParameterValue', $_.FullName)
		}
}
# REF: https://stackoverflow.com/questions/502002/how-do-i-move-a-file-to-the-recycle-bin-using-powershell
