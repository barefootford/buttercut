# Holds the system awake while ButterCut processes footage — the Windows
# counterpart of `caffeinate -i`. Run it in the background and kill the PID when
# done; Windows drops the wake request automatically when the process exits.

$signature = '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
$native = Add-Type -MemberDefinition $signature -Name Native -Namespace ButterCutKeepAwake -PassThru

# ES_CONTINUOUS | ES_SYSTEM_REQUIRED: system stays awake, display may sleep.
# Re-asserted on a loop in case anything clears the execution state.
while ($true) {
    [void]$native::SetThreadExecutionState(0x80000001)
    Start-Sleep -Seconds 50
}
