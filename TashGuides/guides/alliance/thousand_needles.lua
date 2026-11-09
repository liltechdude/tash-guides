-- Thousand Needles (Alliance 28-36). Quest ids, givers and coordinates are taken from the
-- QuestieDB Forever data (tests/zdump.lua) and checked by tests/check_guides.lua.
-- The Alliance has no camp in the canyon: this visit is the goblin and gnome racing teams at
-- the Mirage Raceway on the Shimmering Flats, with Ratchet as the way in and out.

TashGuides.RegisterGuide({
    id = "A_THOUSAND_NEEDLES",
    title = "Thousand Needles",
    subtitle = "Levels 28-36",
    faction = "Alliance",
    minLevel = 28, maxLevel = 36,
    area = 400,
    areas = { 17 },          -- Ratchet (The Barrens)
    next = "A_DESOLACE",
    steps = {
        { title = "Ratchet",
            { "talk", 16227, "for the flight path" },
            note = "The boat from Booty Bay docks in Ratchet. Bragok, the flight master, is on the hill above the docks." },
        { title = "Down to the Shimmering Flats",
            { "goto", 32.2, 22.5, "the Great Lift" },
            note = "Follow the road from Ratchet west to the Crossroads, then south through the Barrens to the Great Lift at the southern edge. Give Camp Taurajo a wide berth, and ride the lift down quickly: the guards at the top are Horde." },
        { title = "Mirage Raceway",
            { "goto", 78.0, 77.0, "Mirage Raceway" },
            note = "From the bottom of the lift follow the canyon road east, past Freewind Post, out onto the salt flats. The race track is in the south-east corner." },
        { { "accept", 1104 }, { "accept", 1105 }, { "accept", 1110 }, { "accept", 1111 },
            { "accept", 1175 }, { "accept", 1176 },
            note = "Fizzle and Wizzle Brassbolts and Kravel Koalbeard sit in the middle of the track (78, 77); Pozzik and Trackmaster Zherin are with the goblins on the east side (80-82, 76-78)." },
        { title = "North of the track",
            { "complete", 1105 }, { "complete", 1176 },
            note = "Sparkleshell tortoises crawl along the northern flats (76, 58); Salt Flats Scavengers circle above them to the north-east (81, 64)." },
        { title = "Around the track",
            { "complete", 1175 }, { "complete", 1110 }, { "complete", 1104 },
            note = "Saltstone basilisks are spread all over the flats: Basilisks to the north (75, 60), Crystalhides around the track (80, 75) and Gazers to the south (78, 88). Rocket car rubble lies scattered just north of the track (77, 71), and Scorpid Terrors crawl right around it (79, 77)." },
        { title = "Mirage Raceway",
            { "turnin", 1104 }, { "turnin", 1105 }, { "turnin", 1110 },
            { "turnin", 1175 }, { "turnin", 1176 }, { "accept", 1178 } },
        { title = "Back to Ratchet",
            { "turnin", 1111 }, { "turnin", 1178 },
            note = "Go back up the Great Lift and north through the Barrens to Ratchet. Wharfmaster Dizzywig is on the docks; Gazlowe is in the building on the hill. From Ratchet the Desolace guide takes over." },
    },
})
