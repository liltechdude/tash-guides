-- Alterac Mountains (Alliance 30-34). Quest ids, givers and coordinates are taken from the
-- QuestieDB Forever data (tests/zdump.lua) and checked by tests/check_guides.lua.
-- Alliance has no town in Alterac: every quest is picked up and handed in at Southshore.

TashGuides.RegisterGuide({
    id = "A_ALTERAC",
    title = "Alterac Mountains",
    subtitle = "Levels 30-34",
    faction = "Alliance",
    minLevel = 30, maxLevel = 34,
    area = 36,
    areas = { 267, 130 },
    next = "A_ARATHI",
    steps = {
        { title = "Southshore",
            { "accept", 505 }, { "accept", 500 }, { "accept", 564 }, { "accept", 92432 },
            note = "Magistrate Henry Maleb and Marshal Redpath are in the town hall (48, 59), Darren Malvew by the stables (52, 56) and Emissary Jacques just south of the town hall (48, 60)." },
        { title = "Strahnbrad",
            { "complete", 505 },
            { "accept", 510 }, { "accept", 511 },
            note = "Take the road north past Tarren Mill (keep clear of the Horde guards) into Alterac. Syndicate Footpads and Thieves hold the ruined village of Strahnbrad (57, 67). Syndicate Documents lie in one of the houses (58, 68)." },
        { title = "Lions and ogres",
            { "complete", 564 }, { "complete", 500 },
            note = "Hulking and regular Mountain Lions prowl the slopes east of Strahnbrad (78, 52) and the south of the zone. Crushridge Ogres camp across the middle of the mountains (51, 45)." },
        { title = "Report to Southshore",
            { "turnin", 505 }, { "turnin", 510 }, { "accept", 512 },
            { "turnin", 511 }, { "turnin", 500 }, { "turnin", 564 },
            note = "Maleb, Loremaster Dibbs (50, 57), Redpath and Malvew. Dibbs' follow-up sends you to Ironforge; skip it." },
        { title = "Syndicate spies",
            { "complete", 512 },
            note = "Syndicate Spies camp in the hills north of Strahnbrad (60, 43). Look for the Alterac Signet Ring." },
        { title = "Dalaran",
            { "turnin", 92432 }, { "accept", 92459 }, { "turnin", 92459 },
            note = "Ride west across the mountains to the walls of Dalaran on Lordamere Lake. The Image of Archmage Modera and Archmage Celindra stand outside the dome (14, 60)." },
        { title = "Back to Southshore",
            { "turnin", 512 },
            note = "Hearth or ride back to Southshore and hand the ring to Magistrate Maleb. Next stop: Arathi Highlands." },
    },
})
