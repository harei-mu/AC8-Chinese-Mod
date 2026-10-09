param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Output, [switch]$Setup)
$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell.' }
if ($Setup) {
    $provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $parameters = New-Object CodeDom.Compiler.CompilerParameters
    $parameters.GenerateExecutable = $true
    $parameters.OutputAssembly = $Output
    $parameters.CompilerOptions = '/target:winexe /platform:x64'
    foreach ($reference in @('System.dll','System.Core.dll','System.Windows.Forms.dll','System.Drawing.dll')) { $null = $parameters.ReferencedAssemblies.Add($reference) }
    $result = $provider.CompileAssemblyFromSource($parameters, [IO.File]::ReadAllText($Source))
    if ($result.Errors.HasErrors) { throw ($result.Errors | Out-String) }
} else {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText($Source)) -OutputAssembly $Output -OutputType Library
}
