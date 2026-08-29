@{
    # These three rules are aimed at reusable library cmdlets meant for
    # pipeline composition / PowerShell Gallery distribution. This repo's
    # .ps1 files are either top-level interactive installer scripts (where
    # direct console output *is* the point — Write-Host is Microsoft's own
    # recommendation for that case, not Write-Output/-Information) or small
    # internal helper functions never exposed as public cmdlets, so these
    # three don't fit and are excluded deliberately, not blanket-disabled —
    # every other rule (including the genuine findings this project already
    # fixed: PSAvoidAssignmentToAutomaticVariable, PSUseBOMForUnicodeEncodedFile)
    # still runs. See docs/ARCHITECTURE.md "Linux/Windows abstraction".
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseSingularNouns',
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
