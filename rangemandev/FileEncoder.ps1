Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "File Encoder/Decoder"
$form.Size = New-Object System.Drawing.Size(500, 550)
$form.StartPosition = "CenterScreen"

$label = New-Object System.Windows.Forms.Label
$label.Text = "Select Mode:"
$label.Location = New-Object System.Drawing.Point(20, 20)
$label.AutoSize = $true
$form.Controls.Add($label)

$modeBox = New-Object System.Windows.Forms.ComboBox
$modeBox.Location = New-Object System.Drawing.Point(20, 50)
$modeBox.Size = New-Object System.Drawing.Size(200, 25)
$modeBox.Items.Add("Encode")
$modeBox.Items.Add("Decode")
$modeBox.SelectedIndex = 0
$form.Controls.Add($modeBox)

$pipelineLabel = New-Object System.Windows.Forms.Label
$pipelineLabel.Text = "Pipeline: Binary -> Gzip -> XOR -> Base64 -> XML"
$pipelineLabel.Location = New-Object System.Drawing.Point(20, 80)
$pipelineLabel.AutoSize = $true
$pipelineLabel.Font = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Italic)
$form.Controls.Add($pipelineLabel)

$modeBox.Add_SelectedIndexChanged({
    if ($modeBox.SelectedItem -eq "Encode") {
        $pipelineLabel.Text = "Pipeline: Binary -> Gzip -> XOR -> Base64 -> XML"
    } else {
        $pipelineLabel.Text = "Pipeline: XML -> Base64 -> XOR -> Gzip -> Binary"
    }
})

$fileLabel = New-Object System.Windows.Forms.Label
$fileLabel.Text = "Select File:"
$fileLabel.Location = New-Object System.Drawing.Point(20, 110)
$fileLabel.AutoSize = $true
$form.Controls.Add($fileLabel)

$fileBrowser = New-Object System.Windows.Forms.TextBox
$fileBrowser.Location = New-Object System.Drawing.Point(20, 140)
$fileBrowser.Size = New-Object System.Drawing.Size(300, 25)
$fileBrowser.ReadOnly = $true
$form.Controls.Add($fileBrowser)

$browseBtn = New-Object System.Windows.Forms.Button
$browseBtn.Text = "Browse..."
$browseBtn.Location = New-Object System.Drawing.Point(330, 138)
$browseBtn.Size = New-Object System.Drawing.Size(80, 29)
$browseBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "All Files (*.*)|*.*"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $fileBrowser.Text = $dlg.FileName
    }
})
$form.Controls.Add($browseBtn)

$outputLabel = New-Object System.Windows.Forms.Label
$outputLabel.Text = "Output File:"
$outputLabel.Location = New-Object System.Drawing.Point(20, 180)
$outputLabel.AutoSize = $true
$form.Controls.Add($outputLabel)

$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Location = New-Object System.Drawing.Point(20, 210)
$outputBox.Size = New-Object System.Drawing.Size(300, 25)
$form.Controls.Add($outputBox)

$outputBrowseBtn = New-Object System.Windows.Forms.Button
$outputBrowseBtn.Text = "Browse..."
$outputBrowseBtn.Location = New-Object System.Drawing.Point(330, 208)
$outputBrowseBtn.Size = New-Object System.Drawing.Size(80, 29)
$outputBrowseBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
 #   $dlg.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
    $dlg.Filter = "All Files (*.*)|*.*"
    if ($modeBox.SelectedItem -eq "Encode" -and -not [string]::IsNullOrEmpty($fileBrowser.Text)) {
        $dlg.FileName = [System.IO.Path]::GetFileNameWithoutExtension($fileBrowser.Text) + ".txt"
    }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $outputBox.Text = $dlg.FileName
    }
})
$form.Controls.Add($outputBrowseBtn)

$hashLabel = New-Object System.Windows.Forms.Label
$hashLabel.Text = "MD5 Hashes:"
$hashLabel.Location = New-Object System.Drawing.Point(20, 250)
$hashLabel.AutoSize = $true
$form.Controls.Add($hashLabel)

$resultBox = New-Object System.Windows.Forms.TextBox
$resultBox.Location = New-Object System.Drawing.Point(20, 275)
$resultBox.Size = New-Object System.Drawing.Size(400, 60)
$resultBox.Multiline = $true
$resultBox.ScrollBars = "Vertical"
$resultBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$resultBox.ReadOnly = $true
$form.Controls.Add($resultBox)

$decodeLabel = New-Object System.Windows.Forms.Label
$decodeLabel.Text = "DECODE COMMAND (run on target system):"
$decodeLabel.Location = New-Object System.Drawing.Point(20, 345)
$decodeLabel.AutoSize = $true
$decodeLabel.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($decodeLabel)

$decodeBox = New-Object System.Windows.Forms.TextBox
$decodeBox.Location = New-Object System.Drawing.Point(20, 370)
$decodeBox.Size = New-Object System.Drawing.Size(400, 80)
$decodeBox.Multiline = $true
$decodeBox.ReadOnly = $true
$decodeBox.Font = New-Object System.Drawing.Font("Consolas", 8)
$decodeBox.Text = ""
$form.Controls.Add($decodeBox)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20, 460)
$statusLabel.Size = New-Object System.Drawing.Size(400, 30)
$statusLabel.ForeColor = [System.Drawing.Color]::Green
$statusLabel.Text = ""
$form.Controls.Add($statusLabel)

$processBtn = New-Object System.Windows.Forms.Button
$processBtn.Text = "Process"
$processBtn.Location = New-Object System.Drawing.Point(20, 500)
$processBtn.Size = New-Object System.Drawing.Size(100, 30)
$processBtn.Add_Click({
    $modeBox.Enabled = $false
    $browseBtn.Enabled = $false
    $processBtn.Enabled = $false
    $statusLabel.Text = ""
    $resultBox.Text = ""
    $decodeBox.Text = ""
    
    try {
        $mode = $modeBox.SelectedItem.ToString()
        $inputFile = $fileBrowser.Text
        
        if ([string]::IsNullOrEmpty($inputFile) -or -not (Test-Path $inputFile)) {
            throw "Please select a valid input file"
        }
        
        $outputFile = $outputBox.Text
        if ([string]::IsNullOrEmpty($outputFile)) {
            if ($mode -eq "Encode") {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($inputFile)
                $outputFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($inputFile), "$baseName.out.txt")
                $outputBox.Text = $outputFile
            } else {
                throw "Please specify an output file for decoding"
            }
        }
        
        if ($mode -eq "Encode") {
            $bytes = [System.IO.File]::ReadAllBytes($inputFile)
            $key = [System.Text.Encoding]::ASCII.GetBytes("thisisfine")
            
            # Gzip compress
            $ms = New-Object System.IO.MemoryStream
            $gzip = New-Object System.IO.Compression.GZipStream([System.IO.Stream]$ms, [System.IO.Compression.CompressionMode]::Compress)
            $gzip.Write($bytes, 0, $bytes.Length)
            $gzip.Dispose()
            $compressed = $ms.ToArray()
            $ms.Dispose()
            
            # XOR with key
            $xored = New-Object byte[] $compressed.Length
            for ($i = 0; $i -lt $compressed.Length; $i++) {
                $xored[$i] = $compressed[$i] -bxor $key[$i % $key.Length]
            }
            
            # Base64 encode
            $base64 = [Convert]::ToBase64String($xored)
            
            # Save as XML
            $base64 | Export-Clixml -Path $outputFile
            
            $inputHash = Get-FileHash -Path $inputFile -Algorithm MD5
            $outputHash = Get-FileHash -Path $outputFile -Algorithm MD5
            $resultBox.Text = "Input MD5:  $($inputHash.Hash)`nOutput MD5: $($outputHash.Hash)"
            $statusLabel.Text = "Encoded successfully to $outputFile (Gzip->XOR->Base64->XML)"
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
            $outFileName = [System.IO.Path]::GetFileName($outputFile)
            $inFileName = [System.IO.Path]::GetFileName($inputFile)
            $decodeBox.Text = "`$b=[Convert]::FromBase64String(Import-Clixml '$outFileName');`$k=[Text.Encoding]::ASCII.GetBytes('thisisfine');`$c=0..`$b.Length|%{`$b[$_]-bxor`$k[$_%10]};`$ms=[IO.MemoryStream]::new(`$c);`$gs=[IO.Compression.GZipStream]::new(`$ms,[IO.Compression.CompressionMode]::Decompress);`$d=[byte[]]::new(`$ms.Length);`$gs.Read(`$d,0,`$d.Length);[IO.File]::WriteAllBytes('$inFileName.decoded',`$d)"
        }
        else {
            $base64 = Import-Clixml -Path $inputFile
            $key = [System.Text.Encoding]::ASCII.GetBytes("thisisfine")
            
            # Base64 decode
            $xored = [Convert]::FromBase64String($base64)
            
            # XOR with key
            $compressed = New-Object byte[] $xored.Length
            for ($i = 0; $i -lt $xored.Length; $i++) {
                $compressed[$i] = $xored[$i] -bxor $key[$i % $key.Length]
            }
            
            # Gzip decompress
            $ms = [System.IO.MemoryStream]::new($compressed)
            $gzip = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
            $buffer = [byte[]]::new(1024)
            $outMs = [System.IO.MemoryStream]::new()
            while ($true) {
                $len = $gzip.Read($buffer, 0, $buffer.Length)
                if ($len -le 0) { break }
                $outMs.Write($buffer, 0, $len)
            }
            $gzip.Dispose()
            $ms.Dispose()
            $outMs.Position = 0
            $decoded = $outMs.ToArray()
            $outMs.Dispose()
            
            [System.IO.File]::WriteAllBytes($outputFile, $decoded)
            
            $inputHash = Get-FileHash -Path $inputFile -Algorithm MD5
            $outputHash = Get-FileHash -Path $outputFile -Algorithm MD5
            
            $resultBox.Text = "Input MD5:  $($inputHash.Hash)`nOutput MD5: $($outputHash.Hash)"
            $statusLabel.Text = "Decoded successfully to $outputFile (XML->Base64->XOR->Gzip)"
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
        }
    }
    catch {
        $statusLabel.Text = "Error: $_"
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
    }
    finally {
        $modeBox.Enabled = $true
        $browseBtn.Enabled = $true
        $processBtn.Enabled = $true
    }
})
$form.Controls.Add($processBtn)

$cancelBtn = New-Object System.Windows.Forms.Button
$cancelBtn.Text = "Close"
$cancelBtn.Location = New-Object System.Drawing.Point(370, 500)
$cancelBtn.Size = New-Object System.Drawing.Size(100, 30)
$cancelBtn.Add_Click({ $form.Close() })
$form.Controls.Add($cancelBtn)

$form.Size = New-Object System.Drawing.Size(500, 580)

$form.ShowDialog()
