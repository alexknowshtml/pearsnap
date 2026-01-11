#!/bin/bash
# Reset Pearsnap permissions when they get stuck after a rebuild
# This clears the TCC database entries so you can re-add the app fresh

echo "This will reset Pearsnap's permission entries."
echo "You'll need to re-grant permissions after running this."
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Resetting Accessibility permission for Pearsnap..."
    tccutil reset Accessibility com.alexhillman.Pearsnap 2>/dev/null || true
    
    echo "Resetting Screen Recording permission for Pearsnap..."
    tccutil reset ScreenCapture com.alexhillman.Pearsnap 2>/dev/null || true
    
    echo ""
    echo "Done! Now:"
    echo "1. Open Pearsnap"
    echo "2. Grant permissions when prompted"
    echo ""
    echo "Or run: open /Applications/Pearsnap.app"
else
    echo "Cancelled."
fi
