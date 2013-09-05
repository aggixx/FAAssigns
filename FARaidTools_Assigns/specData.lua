-- rdps: Includes Hunters
-- mdps
-- spell: A ranged DPS that casts spells to deal damage.
-- phys: All melee DPS and hunters
-- petc: A class with a pet that can tank.
-- multidot: A ranged spec that can multidot

RTA_specData = {
  [62] = { -- Arcane Mage
    ["rdps"] = true,
    ["dps"] = true,
    ["spell"] = true,
  },
  [63] = { -- Fire Mage
    ["rdps"] = true,
    ["dps"] = true,
    ["spell"] = true,
  },
  [64] = { -- Frost Mage
    ["rdps"] = true,
    ["dps"] = true,
    ["spell"] = true,
  },
  [65] = { -- Holy Paladin
    ["rheal"] = true,
    ["heal"] = true,
  },
  [66] = { -- Protection Paladin
    ["tank"] = true,
  },
  [70] = { -- Retribution Paladin
    ["mdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
  },
  [71] = { -- Arms Warrior
    ["mdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
  },
  [72] = { -- Fury Warrior
    ["mdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
  },
  [73] = { -- Protection Warrior
    ["tank"] = true,
  },
  [102] = { -- Balance Druid
    ["rdps"] = true,
    ["dps"] = true,
    ["spell"] = true,
    ["multidot"] = true,
  },
  [103] = { -- Feral Druid
    ["mdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
  },
  [104] = { -- Guardian Druid
    ["tank"] = true,
  },
  [105] = { -- Restoration Druid
    ["rheal"] = true,
    ["heal"] = true,
  },
  [250] = { -- Blood Death Knight
    ["tank"] = true,
  },
  [251] = { -- Frost Death Knight
    ["mdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
    ["nosolo"] = true,
  },
  [252] = { -- Unholy Death Knight
    ["mdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
    ["nosolo"] = true,
  },
  [253] = { -- Beast Mastery Hunter
    ["rdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
    ["petc"] = true,
  },
  [254] = { -- Marksman Hunter
    ["rdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
    ["petc"] = true,
  },
  [255] = { -- Survival Hunter
    ["rdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
    ["petc"] = true,
  },
  [256] = { -- Discipline Priest
    ["rheal"] = true,
    ["heal"] = true,
    ["hnosolo"] = true,
  },
  [257] = { -- Holy Priest
    ["rheal"] = true,
    ["heal"] = true,
    ["hnosolo"] = true,
  },
  [258] = { -- Shadow Priest
    ["rdps"] = true,
    ["dps"] = true,
    ["spell"] = true,
    ["multidot"] = true,
  },
  [259] = { -- Assassination Rogue
    ["mdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
  },
  [260] = { -- Combat Rogue
    ["mdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
  },
  [261] = { -- Subtlety Rogue
    ["mdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
  },
  [262] = { -- Elemental Shaman
    ["rdps"] = true,
    ["dps"] = true,
    ["spell"] = true,
    ["nosolo"] = true,
  },
  [263] = { -- Enhancement Shaman
    ["mdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
    ["nosolo"] = true,
  },
  [264] = { -- Restoration Shaman
    ["rheal"] = true,
    ["heal"] = true,
    ["hnosolo"] = true,
  },
  [265] = { -- Affliction Warlock
    ["rdps"] = true,
    ["dps"] = true,
    ["spell"] = true,
    ["multidot"] = true,
    ["petc"] = true,
  },
  [266] = { -- Demonology Warlock
    ["rdps"] = true,
    ["dps"] = true,
    ["spell"] = true,
    ["multidot"] = true,
    ["petc"] = true,
  },
  [267] = { -- Destruction Warlock
    ["rdps"] = true,
    ["dps"] = true,
    ["spell"] = true,
    ["multidot"] = true,
    ["petc"] = true,
  },
  [268] = { -- Brewmaster Monk
    ["tank"] = true,
  },
  [269] = { -- Windwalker Monk
    ["mdps"] = true,
    ["dps"] = true,
    ["phys"] = true,
  },
  [270] = { -- Mistweaver Monk
    ["mheal"] = true,
    ["heal"] = true,
  },
}