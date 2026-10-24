-- WoW: Forever has no pandemic window: refreshing an aura carries nothing
-- over, so the cooldown manager never marks one and the Pandemic state of
-- the cooldown manager aura rule (retail/monitors/CdmAuraMonitor.lua) could
-- never fire. The state is left out and its alert hidden.
local rule = WowVision.monitors.CdmAuraStateRule
rule.hasPandemic = false
rule:updateFields({
    { key = "pandemic", showInUI = false },
})
