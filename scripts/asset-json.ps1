param(
    [Parameter(Mandatory)][ValidateSet('export', 'import')][string]$Mode,
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
foreach ($dependency in @('Newtonsoft.Json', 'ZstdSharp', 'UAssetAPI')) {
    [System.Reflection.Assembly]::LoadFrom((Join-Path $projectRoot "tools/asset-api/$dependency.dll")) | Out-Null
}
$mapping = [UAssetAPI.Unversioned.Usmap]::new((Join-Path $projectRoot 'tools/ac8-override-toolkit/Mappings.usmap'))
if ($Mode -eq 'export') {
    $asset = [UAssetAPI.UAsset]::new([IO.Path]::GetFullPath($Source), [UAssetAPI.UnrealTypes.EngineVersion]::VER_UE5_4, $mapping, 0, 0)
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Destination), $asset.SerializeJson($true), [Text.UTF8Encoding]::new($false))
} else {
    $asset = [UAssetAPI.UAsset]::DeserializeJson([IO.File]::ReadAllText([IO.Path]::GetFullPath($Source)))
    $asset.Mappings = $mapping
    $asset.Write([IO.Path]::GetFullPath($Destination))
}
Write-Output "$Mode completed: $Destination"
