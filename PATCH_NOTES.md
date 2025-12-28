# Fishing Info Panel - Patch Notes

## [1.1.3] - 2024-12-30

### [FIX]
- Fixed fishing skill display to properly show base skill vs modifiers
- Updated skill ranges for modern WoW (300 skill cap instead of 450+)
- Improved catch messages to distinguish base skill from lure/buff modifiers

### [ENHANCEMENT]
- Skill view now shows "Fishing Skill: 285 (+15) = 300" format when modifiers are active
- Catch messages now show "(285+15)" format to clarify skill breakdown
- Cleaner display when no fishing modifiers are active

## [1.1.2] - 2024-12-30

### [FIX]
- Fixed PMF calculations not displaying values by adding appropriate placeholders
- Shows "---" when insufficient cast data, "n/a" when no catch data, ">1h" for long durations
- Fixed "Item XXXXX" display issue by showing "Loading..." with proper item info refresh
- Added GET_ITEM_INFO_RECEIVED event handler to update display when item data becomes available

### [ENHANCEMENT]
- Added question mark icon placeholder for items still loading
- Improved data readiness indicators throughout the UI

## [1.1.1] - 2024-12-30

### [FIX]
- Added error handling for PMF (Probability Mass Function) calculations to prevent math errors
- Protected against edge cases where probability equals 1 or 0 in time-to-catch calculations
- Added debug logging for PMF computation errors when debug mode is enabled

### [ENHANCEMENT]
- Added visual indicators for cast time statistics readiness status
- Shows "[Cast history warming up X/3]" in orange when collecting initial cast time data
- Shows "[Cast history ready]" in green when sufficient data collected for PMF calculations (3+ casts)
- Improved table column alignment for better readability
- Center-aligned Count, Percentage, and Next columns for cleaner visual presentation

## [1.1.0] = 2024-12-28

### [FEATURE]
- Added catch rate tracking with fish/hour projection based on 5-minute rolling window
- Displays real-time catch rate at bottom of panel showing projected fish per hour
- Added cast time tracking with mean and median statistics
- Tracks time from fishing cast to loot window for performance analysis
- Projected time-to-catch for session fish based on historical data (95% confidence range)
- Actual time-to-catch for session fish (from last catch or beginning of session)

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
