# Holds the system awake while ButterCut processes footage — the Windows
# counterpart of `caffeinate -i`. Don't run this directly: lib/buttercut/
# keep_awake.rb starts and stops it, and is what the skills call on both
# platforms. Windows drops the wake request automatically when this exits.

$signature = '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
$native = Add-Type -MemberDefinition $signature -Name Native -Namespace ButterCutKeepAwake -PassThru

# Matches KeepAwake::MAX_SECONDS: longer than any real footage run, so that a
# session which dies before stopping this doesn't leave a machine that never
# idle-sleeps again.
$deadline = (Get-Date).AddHours(12)

# ES_CONTINUOUS | ES_SYSTEM_REQUIRED: system stays awake, display may sleep.
# Re-asserted on a loop in case anything clears the execution state.
while ((Get-Date) -lt $deadline) {
    [void]$native::SetThreadExecutionState(0x80000001)
    Start-Sleep -Seconds 50
}
