### Summary
This is a massive refactor of the codebase thanks to Claude Fable 5. The UI has been entirely redone to increase ease of development and efficiency. Many long-standing UI focus issues have been fixed and overall the game should feel much smoother now.

### All Versions
* Fixed some rare instances of options screen controls having incorrect or missing tooltips.
* Finally fixed the gossip window acting unpredictably when available dialogue options changed. Additionally the new text is automatically read out.
* Dropdown menus are now fully supported, including submenus.
* The addon now tracks per character and global settings separately. By default most things are global; this can be changed per module via its context menu in the WowVision settings.
* Fixed a bug where you could not tab out of certain edit fields.
* Added support for wall/collision detection. If the addon detects you are moving slower than you should be, it will play sounds indicating a collision (this  replicates Sku's behavior.)
* Added support for fall detection. It can be configured to speak when you  begin to fall. It will also play an ascending series of tones as you fall (this works identically to how Sku's did and uses the same sounds.)
* Added propper support for Feaux Hybrid Scroll frames (aka my arch enemy.) Frames that would cause errors when scrolled will no longer do so. Unfortunately however I cannot implement the home and end keys to jump to the first or last item within these. These frames include the who list and the glyph frames for various versions of the game.
* Fixed a bug where home and end would sometimes act unexpectedly, particularly within nested containers.
* Added support for the rest of the options screen.
* Fixed a bug where certain popups in the options screen would softlock the game.

### Modern
* Added support for the bags window.

#### Forever
* fixed a number of issues with the options window introduced in WoW Forever.
* Added support for the character pane, including the equipment manager.

#### Retail
* Added support for the bags window.

### Classic
* Fixed a bug where edit fields for spell IDs (for example in monitors) would behave extremely inconsistently and often not actually set the spell ID correctly.
* Added initial support for the social tab, including friends, ignore, and the who list.
* Added scanner (todo: explain.)

#### The Burning Crusade Classic
* Updated the TBC speech module to use the retail speech module. Speech output for TBC works again.

#### Mists of Pandaria Classic
* Fixed a number of issues with the mounts tab of the collections pane.
* Add support for the Core Abilities and What Has Changed tabs of the spellbook.