#!/bin/bash
# Restart Harbr

echo "Restarting Harbr..."
launchctl unload ~/Library/LaunchAgents/com.harbr.plist 2>/dev/null
sleep 0.5
launchctl load ~/Library/LaunchAgents/com.harbr.plist
echo "Harbr restarted!"
