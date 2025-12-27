# Fishing Info Panel - Patch Notes

## [Unreleased] -

### [ENHANCEMENT]
- Updated catch display to include previously caught fish with zero session counts
- Items not caught in current session appear in gray with 0.0% to show historical completeness

## [1.0.0] - 2024-12-27

### [FEATURE]
- Initial release of Fishing Info Panel
- Tracks fishing catches by zone with session vs all-time comparison
- Color-coded percentages: green (above average), red (below average), white (normal)
- Automatic junk item categorization and percentage tracking
- Skill-based fishing statistics tracking in background
- Configuration system with catch message and debug logging toggles
- Support for skill view mode to analyze catches by fishing skill ranges
- Real-time catch logging with current fishing skill display

### [ENHANCEMENT]
- Smart junk percentage colors relative to all-time averages when viewing session data
- Comprehensive slash command interface (/fip, /fip skill, /fip catch, /fip debug, /fip config)
- Moveable panel with session/all-time toggle functionality

### [FIX]
- Reliable fishing loot detection using IsFishingLoot() API
- Proper handling of fishing skill modifiers from lures and equipment
- Safe percentage calculations to prevent division by zero errors
