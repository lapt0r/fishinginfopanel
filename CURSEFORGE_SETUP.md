# CurseForge Publishing Setup

This guide explains how to set up automatic publishing to CurseForge using GitHub Actions.

## Prerequisites

1. A CurseForge account
2. Your addon project created on CurseForge
3. A CurseForge API token

## Setup Steps

### 1. Get Your CurseForge API Token

1. Log in to [CurseForge](https://www.curseforge.com/)
2. Go to your account settings
3. Navigate to "API Tokens" section
4. Click "Generate Token"
5. Copy the generated token (you won't be able to see it again!)

### 2. Get Your Project ID

1. Go to your addon's CurseForge page
2. Look for the Project ID in:
   - The URL (e.g., `https://www.curseforge.com/wow/addons/12345-fishing-info-panel`)
   - The "About Project" section on the right sidebar

### 3. Add Token to GitHub Secrets

1. Go to your GitHub repository
2. Click on "Settings" tab
3. Navigate to "Secrets and variables" → "Actions"
4. Click "New repository secret"
5. Add a secret named `CF_API_KEY` with your CurseForge API token as the value

### 4. Update the Workflow File

Edit `.github/workflows/release.yml` and replace `PROJECT_ID` with your actual CurseForge project ID.

## Creating a Release

The workflow triggers automatically when you create a version tag:

```bash
# Create a tag for your release
git tag v1.0.0

# Push the tag to GitHub
git push origin v1.0.0
```

The workflow will:
1. Package your addon into a zip file
2. Upload it to CurseForge
3. Create a GitHub release (if using the packager action)

## Choosing Between Actions

The workflow file includes two options:

1. **BigWigsMods/packager** (recommended for WoW addons)
   - Automatically handles TOC file processing
   - Supports multiple platforms (CurseForge, WoWInterface, Wago)
   - More features for WoW addon development

2. **itsmeow/curseforge-upload** (simpler alternative)
   - Basic CurseForge upload functionality
   - More control over the zip file contents
   - Good for simple upload needs

Choose the one that best fits your needs and comment out the other in the workflow file.

## Troubleshooting

- **Authentication Error**: Make sure your `CF_API_KEY` secret is correctly set
- **Project Not Found**: Verify your project ID is correct
- **Invalid Game Version**: Update the game version in the workflow to match current WoW version
