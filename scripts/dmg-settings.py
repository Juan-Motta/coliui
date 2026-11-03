# dmgbuild settings for the ColiUI installer window (DmgInstaller.dc.html).
# Run by scripts/make-dmg.sh: dmgbuild -s scripts/dmg-settings.py -D app=build/ColiUI.app "<volume name>" <dmg>
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild injects `defines`)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"

background = "Resources/dmg-background.tiff"
# Content size; it matches the 660 x 400 background. With hidden files shown (Cmd-Shift-.), Finder also
# lists .background.tiff and .VolumeIcon.icns below the icons and adds a scroll bar; by default it doesn't.
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 128
text_size = 13
arrange_by = None
label_pos = "bottom"
icon_locations = {
    app_name: (180, 184),
    "Applications": (480, 184),
}
