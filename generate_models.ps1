$dirs = Get-ChildItem -Path "packages\*", "services\*", "app" -Directory
foreach ($dir in $dirs) {
    if (Test-Path "$($dir.FullName)\pubspec.yaml") {
        $content = Get-Content "$($dir.FullName)\pubspec.yaml"
        if ($content -match "build_runner") {
            Write-Host "Generating models for $($dir.Name)..."
            Push-Location $dir.FullName
            flutter pub get
            dart run build_runner build --delete-conflicting-outputs
            Pop-Location
        }
    }
}
Write-Host "Code generation complete."
