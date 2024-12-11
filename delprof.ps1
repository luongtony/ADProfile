# Prompt for the username
$username = Read-Host -Prompt "Enter username of profile to delete"

# Get the user profile matching the specified username
$userProfile = Get-WmiObject -Class Win32_UserProfile | Where-Object { $_.LocalPath.split('\')[-1] -eq $username }

if ($userProfile) {
    # Confirm before deleting
    $confirmation = Read-Host "Are you sure you want to delete the profile for '$username'? (Y/N)"
    if ($confirmation -eq 'Y') {
        # Delete the user profile
        $userProfile.Delete()
        Write-Output "Profile for user '$username' deleted successfully."
    } else {
        Write-Output "Profile deletion canceled."
    }
} else {
    Write-Output "Profile for user '$username' not found."
}
